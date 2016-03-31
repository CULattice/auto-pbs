#!/bin/sh

##########################################
#                                       #
#   launch_auto_pbs.sh                  #
#                                       #
#   Created by William Jay on 3/31/16.  #
#                                       #
#########################################

#   Remarks:
#       This script launches a PBS script that resubmits itself, e.g., for
#       generating a stream of gauge configurations.
#       The current version is a one-liner but a future version may include the
#       option to specify the name of the stream.

qsub -A multirep wjay_multirep_auto_PBS.sh