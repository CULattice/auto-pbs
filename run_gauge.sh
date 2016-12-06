#!/bin/bash

##########################################################
# Bourne shell script for submitting a serial job to the #
# PBS queue using at Fermilab.                           #
##########################################################

######################
# The PBS directives #
######################

# Options appearing below:
# -S Chooses the shell
# -v Passes the folowing environmental variables to the parallel jobs
# -d Chooses a directory for the output "logfile" of the script
# -j Joins output and error files
# -l Chooses "job-size" parameters like nodes or walltime
# -m Chooses messaging options. "n" disables email messaging.

# Options that appear when this job is resubmitted
# -A Chooses the allocation for the submission
# -N Chooses the name of the job to appear in the queue ("stream name")

#PBS -S /bin/bash
#PBS -v PATH,LD_LIBRARY_PATH,PV_NCPUS,PV_LOGIN,PV_LOGIN_PORT
#PBS -d /home/wjay/multirep
#PBS -j oe
#PBS -l nodes=4
#PBS -l walltime=24:00:00
#PBS -m n
#PBS -q bc

##########################################
# Positional arguments from command line #
##########################################

#this_script=${0}

nx=${1}
nt=${2}
beta=${3}
k4=${4}
k6=${5}

exec=${6}
configs_to_run=${7}
config_limit=${8}
nstep2=${9}
nstep1=${10}

rootstore=${11}

A=${12}
N=${13}

this_script="${rootstore}/run_gauge.sh"

# Bundle the command line arguments for resubmission
args="${nx} ${nt} ${beta} ${k4} ${k6} ${exec} ${configs_to_run} ${config_limit} ${nstep2} ${nstep1} ${rootstore} ${A} ${N}"

echo "Got the following options from the command line:"
echo "nx ${nx}"
echo "nt ${nt}"
echo "beta ${beta}"
echo "k4 ${k4}"
echo "k6 ${k6}"
echo "exec ${exec}"
echo "configs_to_run ${configs_to_run}"
echo "config_limit ${config_limit}"
echo "nstep2 ${nstep2}"
echo "nstep1 ${nstep1}"
echo "rootstore ${rootstore}"
echo "A ${A}"
echo "N ${N}"

echo "The name of this script is:"
echo "${this_script}"

########################################
# Tuning other common "run parameters" #
########################################

gammarat=125

max_cg_iterations=500
max_cg_restarts=10
error_per_site="1.0e-8"

trajecs=10
traj_length="1.0"

label="1"

#######################################
# Directories and other general names #
#######################################
# stream      : Used in many different names. Similar to "kind" in Tom's scripts.
# scratchdir  : Lives on a "worker node" and files are staged to this directory
# exec        : Is the binary that does the real computation
# execdir     : Is the home of "exec"
# rootstore   : Is where all "archival" long-term storage lives
# cfgstore    : Is the folder for gauge configurations
# outstore    : Is the folder for output files
# cooldown_file   : The file with "cooldown" info, e.g., time between submissions.

stream="${nx}${nt}_b${beta}_kf${k4}_kas${k6}"

scratchdir="/scratch/multirep_scratch/${stream}"
execdir="/home/wjay/bin/"

mpi_binary="/usr/local/mvapich/bin/mpirun"

# rootstore defined as input variable
cfgstore="${rootstore}/Gauge${stream}_${label}"
outstore="${rootstore}/Out${stream}_${label}"

cooldown_file="${rootstore}/Misc/${stream}_cooldown.dat"
delay_sub_file="${rootstore}/Misc/delay_sub_list.dat"

####################################
# Cores, CPUs, and trajectory info #
####################################
# configs_to_run : the number of configurations run by a single submission
# config_limit : the total number of configurations for the entire stream
# nNodes       : the number of nodes, which should agree with the PBS directive
# coresPerNode : the number of cores on each node, which is machine dependent
# nCores       : the total number of cores for the job

nNodes=$[`cat ${PBS_NODEFILE} | wc --lines`]
(( nNodes= 0 + nNodes ))
coresPerNode=`cat /proc/cpuinfo | grep -c processor`
(( nCores = nNodes * coresPerNode ))

###############
# Error codes #
###############

E_FAILSAFE=50
E_CONCURRENT_JOB=51
E_MISMATCH_CONFIG=60
E_NOTNUMERIC_CONFIG=61
E_CACHE_CP_FAIL=62
E_JOB_INCOMPLETE=63

######################################################################
# Check the failsafe: if the failsafe file exists, stop immediately! #
######################################################################

if [ -e "/home/wjay/multirep/failsafe.multirep" ]
then
    echo "Failsafe engaged - terminating."
    exit $E_FAILSAFE
fi

##########################################################################
# Check for the existance of the "cooldown" thrashing-prevention file.   #
# If not present, make a cooldown file with initial "timestamp" of zero. #
##########################################################################

if [[ ! -e $cooldown_file ]]
then
    `echo "0" > $cooldown_file`
fi

######################################################
#   Check for competing jobs on the same evolution.  #
#   Note: In Ethan's version of the script, his awk  #
#   command leads with '/nid/ ... ', which I omit.   #
######################################################

echo "==========================================="
qstat | grep wjay
echo "==========================================="
other_jobs=`qstat -l | grep ${N} | awk '{ if ($3 == "wjay" && $5 == "R") print $1}' | grep -v ${PBS_JOBID}`

if [[ $other_jobs ]]
then
    echo "Warning: concurrent job(s) found running on same stream:"
    echo "$other_jobs"
    echo

    ######################################################################
    # Resubmit this script.                                              #
    # Resubmission occurs after checking cooldown to avoid thrashing.    #
    # If concurrent jobs are running, exit after resubmission or after   #
    # issuing a thrashing warning.                                       #
    # Note the hardcoded time of 1800 (seconds) below, which simply says #
    # that successful jobs require more than 30 minutes to run.          #
    ######################################################################

    curr_time_utc=`date +%s`
    prev_time_utc=`cat ${cooldown_file}`
    let "diff_time_utc=${curr_time_utc} - ${prev_time_utc}"

    if [[ $diff_time_utc -gt 1800 ]]
    then
        echo "$curr_time_utc" > ${cooldown_file}
        cd ${PBS_O_WORKDIR}
        /usr/bin/rsh bc1p "/usr/local/pbs/bin/qsub -A ${A} -N ${N} ${this_script} -F \"${args}\""
    else
        # TODO: Add support for a cron job to monitor delay_sub_file
        echo "Warning: thrashing detected - attempted to submit twice within ${diff_time_utc} sec."
        # echo "${PBS_O_WORKDIR}/${this_script}" >> ${delay_sub_file}
    fi

    exit $E_CONCURRENT_JOB
fi

#########################
# Print basic job info. #
#########################

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

#######################################
# Determine the configuration number. #
#######################################

# The naming conventions for output files and gauge configurations is:
# output :
#   out_1632_b7.75_kf0.1290_kas0.1308_10
#   out_${ns}${nt}_b${beta}_kf${k4}_kas${k6}_${count}
#   out_${stream}_${count}
# gauge configurations :
#   cfg_1632_b7.75_kf0.1290_kas0.1308_10
#   cfg_${ns}${nt}_b${beta}_kf${k4}_kas${k6}_${count}
#   cfg_${stream}_${count}
#
# The goal of the sed processing is to extract the *number* of the latest gauge
# configuration that has run. Typically cfgstore will house gauge configurations
# and their associated *.info files. When looking for the latest gauge
# configuration, our processing must remember to ignore *.info files.
#
# Note: Ethan's version ran Chroma, which required a separate input file and a
# separate gauge configuration file. His version checked to make sure both files
# existed together. With MILC we can generate input files "on the fly."

read_num_cfg=$[`ls ${cfgstore}/ | sed '/.info/d' | awk -F'_' '{print $NF}' | sort -n | tail -1`]
read_num_out=$[`ls ${outstore}/ | awk -F'_' '{print $NF}' | sort -n | tail -1`]

if [ "$read_num_cfg" != "$read_num_out" ]
then
    echo "Mismatched configuration numbers in archive $read_num_cfg, $read_num_out!"
    exit $E_MISMATCH_CONFIG
fi

read_num=${read_num_cfg}
last_num=0

case "$read_num" in
    ""      ) echo "Failed to locate final configuration!"; exit $E_NOTNUMERIC_CONFIG;;
    *[!0-9]*) echo "Non-numeric final configuration ${read_num}!"; exit $E_NOTNUMERIC_CONFIG;;
    *       ) last_num=${read_num};;
esac

let "next_num=${last_num}+1"
let "final_num=${last_num}+${configs_to_run}"

#######################################################################
# Don't run past the configuration limit set above in "config_limit"! #
# If the next configuration exceeds the limit, stop immediately.      #
# If the final configuration exceeds the limit, reset it to the limit.#
#######################################################################

if [[ "$next_num" -gt "$config_limit" ]]
then
    echo "Next configuration in line ${next_num} exceeds limit ${config_limit}!"
    exit $E_CONFIG_LIMIT
fi

if [[ "$final_num" -gt "$config_limit" ]]
then
    echo "Final configuration ${final_num} exceeds limit ${config_limit} - resetting."
    final_num=$config_limit
fi

echo "Last trajectory number found in this stream: ${last_num}"

lastcfg="cfg_${stream}_${last_num}"

######################################################
# Stage files into scratch area on worker node(s).   #
# First wipe and (re)create scratchdir.              #
# Next copy over the binary (exec) and saved config. #
######################################################

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
# Loop over configuration number, execute binary, and move results to archive. #
################################################################################

work_num="${next_num}"
while [[ "$work_num" -le "$final_num" ]]
do
    echo "Starting configuration ${work_num}."
   
    workcfg="cfg_${stream}_${work_num}"
    workcfginfo="cfg_${stream}_${work_num}.info"
    workout="out_${stream}_${work_num}"

    echo "Executing mpirun..."
    echo

    ###################################################################
    # Execute binary. Note the long here-doc for the MILC input file. #
    ###################################################################

    $mpi_binary -np $nCores $execdir/$exec << LimitStr >> $scratchdir/$workout
prompt 0
nx ${nx}
ny ${nx}
nz ${nx}
nt ${nt}
iseed ${nx}${nt}${work_num}

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
npseudo 4
nlevels 2

## fermion actions

kpid   kap_f       # identifier
kappa  ${k4}  # hopping parameter
csw    1.0         # clover coefficient
# mu     0.0       # chemical potential
nf     2           # how many Dirac flavors
irrep  fund

kpid   kap_as      # identifier
kappa  ${k6} # hopping parameter
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
shift1 .2           # for simulating det(M^dag M + shift1^2)
iters 500          # CG iterations
rstrt 10           # CG restarts
resid 1.0e-6       # CG stopping condition

pfid twom_f
type twomass
kpid kap_f
multip 1
level 2
shift1 .0          # simulates det(M^dag M + shift1^2)/det(M^dag M + shift2^2)
shift2 .2
iters 500
rstrt 10
resid 1.0e-6

pfid onem_as
type onemass
kpid kap_as
multip 1
level 1
shift1 .2
iters 500
rstrt 10
resid 1.0e-6

pfid twom_as
type twomass
kpid kap_as
multip 1
level 2
shift1 .0
shift2 .2
iters 500
rstrt 10
resid 1.0e-6

## update params
warms 0
trajecs ${trajecs}
traj_length ${traj_length}
traj_between_meas 1
nstep ${nstep2}     # steps for level 2
nstep ${nstep1}     # steps for level 1
nstep_gauge 6      # steps for level 0
ntraj_safe  5      # how often to do a safe traj
nstep_safe  80     # outer nstep for safe traj

## load/save
reload_serial ${lastcfg}
save_serial ${workcfg}
LimitStr

    #############################################
    # End of long here-doc for MILC input file. #
    #############################################
    echo "Done."
    ls -l

    echo "Archiving output..."
    echo "Current working directory $PWD"
    cp $workout $outstore/
    cp $workcfg $cfgstore/
    cp $workcfginfo $cfgstore/

    rm -rf $lastcfg

    let "last_num = $work_num"
    let "work_num += 1"
    lastcfg=$workcfg
done

##########################################
# Confirm that the job ran successfully. #
##########################################

finalcfg="cfg_${stream}_${final_num}"
finalout="out_${stream}_${final_num}"

if [[ -e $finalcfg && -e $finalout ]]
then
    cd ${PBS_O_WORKDIR}
    echo "Current working directory $PWD"
    echo "/usr/local/pbs/bin/qsub -A ${A} -N ${N} ${this_script} -F \"${args}\""
    /usr/bin/rsh bc1p "/usr/local/pbs/bin/qsub -A ${A} -N ${N} ${this_script} -F \"${args}\""

else
    echo "Critical error: final expected output/cfg not found!"
    exit $E_JOB_INCOMPLETE
fi

echo "Done."
echo "Job completed on "`date`

