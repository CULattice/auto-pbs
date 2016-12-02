# auto-pbs

## General information

README file for "PBS auto-submission" scripts for use on Fermilab clusters.

This package contains a variety of scripts for running jobs at Fermilab which
resubmit themselves, effectively running for as long as desired.

 * ``script-flowchart.pdf`` - Picture of a whiteboard discussion describing the flow the auto-resubmission scripts

 * ``helen.py`` - Script for easily submitting and launching multiple ensembles, which then run with the script run_gauge.sh
 * ``run_gauge.sh`` - Script for run gauge generation code at Fermilab. Accepts a myriad of positional arguments. Best called by a wrapper program like helen.py, although you can also call it directly from the command line.

 * ``run_b7.75_kf0.1290_kas0.1290.sh`` - Script with all values hard-coded and accepting *no* command line physics arguments
 * ``run_fresh_b7.75_kf0.1290_kas0.1290.sh`` - - Script with all values hard-coded and accepting *no* command line physics arguments **AND** that starts from a "fresh" lattice (as opposed to seeding it from some existing lattice)
 * ``launch_auto_PBS.sh`` - Script with an example of how to launch the hard-coded script

Credit: the bash scripts are based heavily on an example scripts due to Ethan Neil. The
algorithm used by the script was first explained to me on a whiteboard by Ethan
(cf. script-flowchart.pdf), although I suspect the general idea must be much older.

## Getting up and running

### Using the all-purpose script

Decide where your "root storage" directory will be for data, and make the directories where things will be saved.
In this "root storage" directory, make the folder ``Misc``.

The following changes may be necessary in **``helen.py``**, which launches the ensembles.

 * Line 56/57: Update with the name of your binary file
 * Line 62: Update with the name of your root storage directory
 * Line 70: Update with the name of your allocation (in our case, it's always ``multirep``).
 * Line 71: Update with the name you would like the job to appear as in the queue. The name should be different for each ensemble or stream, so that multiple ensembles can run simultaneously. Probably the existing name is fine for most situations.
 * Line 85: Update the hard-coded location of the script ``run_gauge.sh``
 
The following changes may be necessary in **``run_gauge.sh``**, which calls MILC code and resubmits itself to the queue.

  * Lines 24 - 36: Update the PBS option as necessary. 
    * Option ``-d`` should be the folder where "logfiles" (with error messages, etc...) are sent
    * Option ``-l`` specifies the number of nodes to use and the walltime to request.
    * Option ``-q`` specifies the queue to use (e.g., ``bc`` or ``test_bc``)
  * Lines 104 - 116: Update the directory structure as necessary.
    * Line 107: ``execdir`` is the directory where your "MILC binary" lives
    * Line 170: change it ``grep`` on your username
    * Line 172: change to your username
    * Lines 245/246: If your file names aren't of the form ``somefilename_count``, where ``count`` is the configuration number, modify the regex processing to extract the configuration number correctly.


### Using the hard-coded script

Quick guide to modifications necessary to get the script up and running for your job.
Action points follow the "TODO" tags below.
DISCLAIMER: This script has a somewhat confused variable naming conventions regarding the words "trajectory" and "configuration", although it has been tested to run correctly.


####   The PBS directives   

 * TODO : Update these parameters as desired.

####   Physics parameters  

All of these parameters should have self-evident names and will obviously change
with each new project.

 * TODO : Update your physics parameters in the PBS script.
 * TODO : Update ``run_traj`` to be the number of configurations you want to run in a
    single submission of the PBS script. In general, the number will depend on
    the walltime requested in the PBS directives.
 * TODO : Update ``traj_limit`` to the final configurations you ultimately want the whole
    stream to generate.

####   Directories and other general names

The autosubmission script assumes that the following directory structure exists.

rootstore : The "root" storage directory which contains all the long-term
            storage folders for gauge configurations and output files.

 * ``rootstore/cfgstore``: Storage folder for gauge configurations.
 * ``rootstore/outstore``: Storage folder for output files.
 * ``rootstore/Misc``: Storage folder for "cooldown" and "delay_sub_list" files

The script does *not* automatically build this directory structrue. It is the
user's responsibility to make sure that the directory strucutre exists before
running the PBS autosubmission script.

The script tries to build the names for rootstore, cfgstore, and outstore using
the various physics paramters. Of course, the idea is that the user should choose
unique and sensible names.

The folder rootstore/Misc has a hard-coded name. Given a user-defined rootstore,
``${rootstore}/Misc`` must exist. (Or the script will need modification.)

 * TODO : Construct the aforementioned directory structure.
 * TODO : Update variable names to agree with your choices for directory names.
 * TODO : Make certain you created the folder ``${rootstore}/Misc``.
 * TODO : Update variable names to agree with the executable, the executable's location,
    and the binary for ``mpirun`` (or whichever of its cousins you prefer).

####   Check the failsafe: if the failsafe file exists, stop immediately!  

 * TODO : Look at, set, and write down or remember the directory where the script
    will search for the failsafe file.

####   Check for competing jobs on the same evolution.  

 * TODO : Modify instances of "wjay" to be your username
 * TODO : If running someplace other than Fermilab, make sure that the long command
    following ``qstat -l | ...`` correctly looks for other jobs. Probably the most
    likely difference will is column placement in the qstat output, as reflected
    in the hard-coded numbers 3 and 5 in the awk command.

####   Resubmit this script.   

 * TODO : Modify the following line to give useful output in case of thrashing:
    echo ``${PBS_O_WORKDIR}/wjay_multirep_auto_PBS.sh >> ${delay_sub_file}``

####   Determine the trajectory number.

The PBS script automatically detects the last configuration and outputfiles
generated by the stream and starts up immediately after them. In order for this
automatic detection to work, the PBS script must know something about where the
trajectory number is stored.

My usage assumes that all output files and gauge configurations end with an
underscore followed by the trajectory number, i.e., ``*_${traj_number}``.

In the case of different file naming conventions or delimiters, changes are
necessary.

 * TODO : As necessary, modify the regex processing to extract trajectory numbers.










