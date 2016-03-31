#!/bin/bash

################################################################################
#                                                                              #
#   Bourne shell script for submitting jobs to the PBS queue at Fermilab.      #
#                                                                              #
#   Remarks:                                                                   #
#       This script generates a stream of gauge configurations, although it    #
#       should be easily adaptable to other jobs. As written, it computes and  #
#       saves (trajecs) and repeats this process (run_traj) times for a grand  #
#       total of (trajecs) x (run_traj) total trajectories. The script then    #
#       resubmits itself and generates more trajectories until the last        #
#       trajectory runs into (traj_limit).                                     #
#                                                                              #
#       When choosing the walltime, keep the number (trajecs) x (run_traj) in  #
#       mind and multiply by the expected time for a single trajectory.        #
#                                                                              #
#       The parameters (trajecs), (run_traj), and (traj_limit) are set below   #
#       in the section titled "Physics parameters."                            #
#                                                                              #
#   TODO: Add support for monitoring delay_sub_file. This feature is currently #
#       deprecated but is likely unnecessary execept when trying to "game" a   #
#       very busy queue.                                                       #
#                                                                              #
################################################################################

##########################
#                        #
#   The PBS directives   #
#                        #
##########################

#    Remarks on options:
#       -S Chooses the shell
#       -v Passes the folowing environmental variables to the parallel jobs
#       -A Chooses the allocation for the submission
#       -N Chooses the name of the job to appear in the queue ("stream name")
#       -d Chooses a directory for the output "logfile" of the script
#       -j Joins output and error files 
#       -l Chooses "job-size" parameters like nodes or walltime
#       -m Chooses messaging options. "n" disables email messaging.

#PBS -S /bin/bash
#PBS -v PATH,LD_LIBRARY_PATH,PV_NCPUS,PV_LOGIN,PV_LOGIN_PORT
#PBS -A multirep
#PBS -N mrep_Nf2_Nas2_1
#PBS -d /home/wjay/multirep
#PBS -j oe
#PBS -l nodes=4
#PBS -l walltime=24:00:00
#PBS -m n
#PBS -q bc

#########################
#                       #
#   Physics parameters  #
#                       #
#########################

#   Remarks:
#       run_traj    : the number of trajectories run by a single submission
#       traj_limit  : the total number of trajectories for the entire stream

nx=16
nt=32
beta="7.75"
kappa_f="0.1290"
kappa_as="0.1308"
gammarat=125

max_cg_iterations=500
max_cg_restarts=10
error_per_site="1.0e-8"

trajecs=10
traj_length="1.0"
nstep="80"

label="1"

run_traj=1
traj_limit=1000

#############################################
#                                           #
#   Directories and other general names     #
#                                           #
#############################################

#   Remarks:
#       stream      : Used in many different names. Similar to "kind" in Tom's scripts.
#           Explicit dependencies on stream are:
#                   - scratchdir
#                   - cfgstore
#                   - outstore
#                   - cooldown_file
#                   - lastcfg
#                   - workcfg
#                   - workcfginfo
#                   - workout
#                   - finalcfg
#                   - finalout
#       stream_name : Must agree with the name from the -n option in PBS directives
#       scratchdir  : Lives on a "worker node" and files are staged to this directory
#       exec        : Is the binary that does the real computation
#       execdir     : Is the home of "exec"
#       rootstore   : Is where all "archival" long-term storage lives
#       cfgstore    : Is the folder for gauge configurations
#       outstore    : Is the folder for output files
#       cooldown_file   : The file with "cooldown" info, i.e., time between submissions.
#
#       delay_sub_file  : *DEPRECATED* (cf. Remarks in opening preamble)

stream="${nx}${nt}_b${beta}_kf${kappa_f}_kas${kappa_as}"
stream_name="mrep_Nf2_Nas2_${label}"

scratchdir="/scratch/multirep_scratch/${stream}"

exec="su4_mrep_phi_bc1_mvapich_O3"
execdir="/home/wjay/bin/"

mpi_binary="/usr/local/mvapich/bin/mpirun"

rootstore="/home/wjay/multirep/Run_SU4_Nf2_Nas2_${nx}${nt}"
cfgstore="${rootstore}/Gauge${stream}_${label}"
outstore="${rootstore}/Out${stream}_${label}"

cooldown_file="${rootstore}/Misc/${stream}_cooldown.dat"
delay_sub_file="${rootstore}/Misc/delay_sub_list.dat"

#########################################
#                                       #
#   Cores, CPUs, and trajectory info    #
#                                       #
#########################################

#   Remarks:
#       run_traj    : the number of trajectories run by a single submission
#       traj_limit  : the total number of trajectories for the entire stream
#       nNodes      : the number of nodes, which should agree with the PBS directive
#       coresPerNode: the number of cores on each node, which is machine dependent
#       nCores      : the total number of cores for the job

nNodes=$[`cat ${PBS_NODEFILE} | wc --lines`]
(( nNodes= 0 + nNodes ))
coresPerNode=`cat /proc/cpuinfo | grep -c processor`
(( nCores = nNodes * coresPerNode ))

#####################
#                   #
#   Error codes     #
#                   #
#####################

E_FAILSAFE=50
E_CONCURRENT_JOB=51
E_MISMATCH_TRAJ=60
E_NOTNUMERIC_TRAJ=61
E_CACHE_CP_FAIL=62
E_JOB_INCOMPLETE=63

#########################################################################
#                                                                       #
#   Check the failsafe: if the failsafe file exists, stop immediately!  #
#                                                                       #
#########################################################################

if [ -e "/home/wjay/multirep/failsafe.multirep" ]
then
    echo "Failsafe engaged - terminating."
    exit $E_FAILSAFE
fi

################################################################################
#                                                                              #
#   Check for the existance of the "cooldown" thrashing-prevention file.       #
#   If not present, make the cooldown file.                                    #
#   The cooldown file is intentionally initialized with a "timestamp" of zero. #
#                                                                              #
################################################################################

if [[ ! -e $cooldown_file ]]
then
    `echo "0" > $cooldown_file`
fi
######################################################
#                                                    #
#   Check for competing jobs on the same evolution.  #
#   Note: In Ethan's version of the script, his awk  #
#   command leads with '/nid/ ... ', which I omit.   #
#                                                    #
######################################################

echo "==========================================="
qstat | grep wjay
echo "==========================================="
other_jobs=`qstat -l | grep ${stream_name} | awk '{ if ($3 == "wjay" && $5 == "R") print $1}' | grep -v ${PBS_JOBID}`

if [[ $other_jobs ]]
then
    echo "Warning: concurrent job(s) found running on same stream:"
    echo "$other_jobs"
    echo

    #########################################################################
    #                                                                       #
    #   Resubmit this script.                                               #
    #   Resubmission occurs after checking cooldown to avoid thrashing.     #
    #   If concurrent jobs are running, exit after resubmission or after    #
    #   issuing a thrashing warning.                                        #
    #                                                                       #
    #   Note the hardcoded time of 1800 (seconds) below, which simply says  #
    #   that successful jobs require more than 30 minutes to run.           #
    #                                                                       #
    #########################################################################

    curr_time_utc=`date +%s`
    prev_time_utc=`cat ${cooldown_file}`
    let "diff_time_utc=${curr_time_utc} - ${prev_time_utc}"

    if [[ $diff_time_utc -gt 1800 ]]
    then
        echo "$curr_time_utc" > ${cooldown_file}
        cd ${PBS_O_WORKDIR}
        /usr/bin/rsh bc1p '/usr/local/pbs/bin/qsub -A multirep /home/wjay/multirep/wjay_multirep_auto_PBS.sh'
    else
        # TODO: Add support for a cron job to monitor delay_sub_file
        echo "Warning: thrashing detected - attempted to submit twice within ${diff_time_utc} sec."
        echo "${PBS_O_WORKDIR}/wjay_multirep_auto_PBS.sh" >> ${delay_sub_file}
    fi

    exit $E_CONCURRENT_JOB
fi

#############################
#                           #
#   Print basic job info.   #
#                           #
#############################

echo "multirep job initiated..."
echo "Job ${PBS_JOBNAME} submitted from ${PBS_O_HOST} on "`date`
echo "Job ID: ${PBS_JOBID}"
echo "List of nodes:"
echo "--------------------"
cat ${PBS_NODEFILE}
echo "--------------------"
nodecount=$[`cat ${PBS_NODEFILE} | wc --lines`]
echo "$nodecount nodes allocated."
echo

################################################################################
#                                                                              #
#   Determine the trajectory number.                                           #
#                                                                              #
################################################################################

#   Remarks:                                                                   #
#       The naming conventions for output files and gauge configurations is:   #
#       output :                                                               #
#           out_1632_b7.75_kf0.1290_kas0.1308_10                               #
#           out_${ns}${nt}_b${beta}_kf${kappa_f}_kas${kappa_as}_${count}       #
#           out_${stream}_${count}                                             #
#       gauge configurations :                                                 #
#           cfg_1632_b7.75_kf0.1290_kas0.1308_10                               #
#           cfg_${ns}${nt}_b${beta}_kf${kappa_f}_kas${kappa_as}_${count}       #
#           cfg_${stream}_${count}                                             #
#                                                                              #
#       The goal of the sed processing is to extract the *number* of the       #
#       latest gauge configuration that has run. Typically cfgstore will house #
#       gauge configurations and their associated *.info files. When looking   #
#       for the latest gauge configuration, our processing must remember to    #
#       ignore *.info files.                                                   #
#                                                                              #
#   Note: Ethan's version ran Chroma, which required a separate input file and #
#   a separate gauge configuration file. His version checked to make sure both #
#   files existed together. With MILC we can generate input files "on the fly."#

read_traj_cfg=$[`ls ${cfgstore}/ | sed '/.info/d' | awk -F'_' '{print $NF}' | sort -n | tail -1`]
read_traj_out=$[`ls ${outstore}/ | awk -F'_' '{print $NF}' | sort -n | tail -1`]

if [ "$read_traj_cfg" != "$read_traj_out" ]
then
    echo "Mismatched trajectory numbers in archive $read_traj_cfg, $read_traj_out!"
    exit $E_MISMATCH_TRAJ
fi

read_traj=${read_traj_cfg}
last_traj=0

case "$read_traj" in
    ""      ) echo "Failed to locate final trajectory!"; exit $E_NOTNUMERIC_TRAJ;;
    *[!0-9]*) echo "Non-numeric final trajectory ${read_traj}!"; exit $E_NOTNUMERIC_TRAJ;;
    *       ) last_traj=${read_traj};;
esac

let "next_traj=${last_traj}+1"
let "final_traj=${last_traj}+${run_traj}"

#########################################################################
#                                                                       #
#   Don't run past the trajectory limit set above in "traj_limit"!      #
#   If the next trajectory exceeds the limit, stop immediately.         #
#   If the final trajectory exceeds the limit, reset it to the limit.   #
#                                                                       #
#########################################################################

if [[ "$next_traj" -gt "$traj_limit" ]]
then
    echo "Next trajectory in line ${next_traj} exceeds limit ${traj_limit}!"
    exit $E_TRAJ_LIMIT
fi

if [[ "$final_traj" -gt "$traj_limit" ]]
then
    echo "Final traj ${final_traj} exceeds limit ${traj_limit} - resetting."
    final_traj=$traj_limit
fi

echo "Last trajectory number found in this stream: ${last_traj}"

lastcfg="cfg_${stream}_${last_traj}"

#########################################################
#                                                       #
#   Stage files into scratch area on worker node(s).    #
#   First wipe and (re)create scratchdir.               #
#   Next copy over the binary (exec) and saved config.  #
#                                                       #
#########################################################

echo "Staging files..."
rm -rf $scratchdir
mkdir -p $scratchdir
# cp $execdir/$exec $scratchdir
cp $cfgstore/$lastcfg $scratchdir

echo "Done."

cd $scratchdir
echo "Working directory: $PWD"
ls -l

################################################################################
#                                                                              #
#   Loop over trajectory number, execute binary, and move results to archive.  #
#                                                                              #
################################################################################

work_traj="${next_traj}"
while [[ "$work_traj" -le "$final_traj" ]]
do
    echo "Starting trajectory ${work_traj}."
   
    workcfg="cfg_${stream}_${work_traj}"
    workcfginfo="cfg_${stream}_${work_traj}.info"
    workout="out_${stream}_${work_traj}"

    echo "Executing mpirun..."
    echo

    #####################################################################
    #                                                                   #
    #   Execute binary. Note the long here-doc for the MILC input file. #
    #                                                                   #
    #####################################################################

    $mpi_binary -np $nCores $execdir/$exec << LimitStr >> $scratchdir/$workout
prompt 0
nx ${nx}
ny ${nx}
nz ${nx}
nt ${nt}
iseed 6721827

## gauge action params
beta ${beta}
# beta_frep_fund 0.0
# beta_frep_asym 0.1
# beta_frep_symm 0.0
# beta_frep_adjt 0.0
gammarat ${gammarat}

# ## SF parameters
# bc_flag alpha
# # no ct_flag in multirep
# ferm_twist_phase 0.2

# alpha_hyp0   .2
# alpha_hyp1   .4
# alpha_hyp2   .6

## fermion observables
max_cg_iterations ${max_cg_iterations}
max_cg_restarts ${max_cg_restarts}
error_per_site ${error_per_site}

## dynamical fermions
nkappas 2
npseudo 2
nlevels 1

## fermion actions

kpid   kap_f       # identifier
kappa  ${kappa_f}  # hopping parameter
csw    1.0         # clover coefficient
# mu     0.0       # chemical potential
nf     2           # how many Dirac flavors
irrep  fund

kpid   kap_as      # identifier
kappa  ${kappa_as} # hopping parameter
csw    1.0         # clover coefficient
# mu     0.0       # chemical potential
nf     2           # how many Dirac flavors
irrep  asym

## pf actions

pfid onem_f        # a unique name, for identification in the outfile
type onemass       # pseudofermion action types: onemass twomass rhmc
kpid kap_f         # identifier for the fermion action
multip 1           # how many copies of this pseudofermion action will exist
level 1            # which MD update level
shift1 0           # for simulating det(M^dag M + shift1^2)
iters 500          # CG iterations
rstrt 10           # CG restarts
resid 1.0e-6       # CG stopping condition

pfid onem_as
type onemass
kpid kap_as
multip 1
level 1
shift1 0
iters 500
rstrt 10
resid 1.0e-6

## update params
warms 0
trajecs ${trajecs}
traj_length ${traj_length}
traj_between_meas 1
nstep ${nstep}     # steps for level 1
nstep_gauge 6      # steps for level 0
ntraj_safe  2      # how often to do a safe traj
nstep_safe  80     # outer nstep for safe traj

## load/save
reload_serial ${lastcfg}
save_serial ${workcfg}
LimitStr

    #################################################
    #                                               #
    #   End of long here-doc for MILC input file.   #
    #                                               #
    #################################################

    echo "Done."
    ls -l

    echo "Archiving output..."
    echo "Current working direction $PWD"
    cp $workout $outstore/
    cp $workcfg $cfgstore/
    cp $workcfginfo $cfgstore/

    rm -rf $lastcfg

    let "last_traj = $work_traj"
    let "work_traj += 1"
    lastcfg=$workcfg
done

#############################################
#                                           #
#   Confirm that the job ran successfully.  #
#                                           #
#############################################

finalcfg="cfg_${stream}_${final_traj}"
finalout="out_${stream}_${final_traj}"

if [[ -e $finalcfg && -e $finalout ]]
then
    cd ${PBS_O_WORKDIR}
    /usr/bin/rsh bc1p '/usr/local/pbs/bin/qsub -A multirep /home/wjay/multirep/wjay_multirep_auto_PBS.sh'

else
    echo "Critical error: final expected output/cfg not found!"
    exit $E_JOB_INCOMPLETE
fi

echo "Done."
echo "Job completed on "`date`

