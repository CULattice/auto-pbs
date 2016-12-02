#!/bin/bash

###############################################################
#    Bourne shell script for submitting a serial job to the   #
#    PBS queue using at Fermilab.                             #
#    Starts a new stream that does not have a seed!           #
###############################################################

##########################
#   The PBS directives   #
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
#PBS -N hmc_168_7.75_0.1290_0.1290
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

nx=16
nt=8
beta="7.75"
kappa_f="0.1290"
kappa_as="0.1290"
gammarat=125

max_cg_iterations=500
max_cg_restarts=10
error_per_site="1.0e-8"

trajecs=10
traj_length="1.0"
nstep="40"

label="1"

#############################################
#                                           #
#   Directories and other general names     #
#                                           #
#############################################

#   Remarks:
#       stream      : Used in many different names. Similar to "kind" in Tom's scripts.
#           Explicit dependencies on stream are:
#                   - scratchdir
#                   - read_traj_cfg
#                   - lastcfg
#                   - workcfg
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
#       delay_sub_file  : *DEPRECATED*

stream="${nx}${nt}_b${beta}_kf${kappa_f}_kas${kappa_as}"
stream_name="mrep_Nf2_Nas2_${label}"

scratchdir="/scratch/multirep_scratch/${stream}"

#exec="su4_mrep_hmc_bc1_mvapich_wj"
exec="su4_mrep_phi_bc1_mvapich_wj"
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
#       nNodes      : the number of nodes, which should agree with the PBS directive
#       coresPerNode: the number of cores on each node, which is machine dependent
#       nCores      : the total number of cores for the job

nNodes=$[`cat ${PBS_NODEFILE} | wc --lines`]
(( nNodes= 0 + nNodes ))
coresPerNode=`cat /proc/cpuinfo | grep -c processor`
(( nCores = nNodes * coresPerNode ))

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

##################################################
#  Execute binary, and move results to archive.  #
##################################################

mkdir -p $scratchdir
cd $scratchdir
echo "Working directory: $PWD"
ls -l

work_traj=0
echo "Starting trajectory ${work_traj}."
   
workcfg="cfg_${stream}_${work_traj}"
workcfginfo="cfg_${stream}_${work_traj}.info"
workout="out_${stream}_${work_traj}"

echo "Executing mpirun..."
echo

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
ntraj_safe  10     # how often to do a safe traj
nstep_safe  80     # outer nstep for safe traj

## load/save
fresh
save_serial ${workcfg}
LimitStr

#################################################
#   End of long here-doc for MILC input file.   #
#################################################

echo "Done."
ls -l

echo "Archiving output..."
echo "Current working direction $PWD"
cp $workout $outstore/
cp $workcfg $cfgstore/
cp $workcfginfo $cfgstore/

echo "Done."
echo "Job completed on "`date`

