# -*- coding: utf-8 -*-
"""
Created on Tue Nov 22 11:35:23 2016

Helen.

Was this the python script that launch'd a thousand jobs
And burnt the Jpsi hours?

@author: wijay
"""
import os

def main():

    ensembles = [
        # (lattice_params,run_params) for each ensemble...
        ({'nx':16,'nt':32,'beta':'7.55','k4':'0.1300','k6':'0.1325'},
         {'configs_to_run':4,'config_limit':60,'exec':'su4_mrep_hmc_bc1_mvapich_wj','nstep2':30,'nstep1':1}),
        ]

    for (lattice_params,run_params) in ensembles:
        cmd = build_cmd(lattice_params,run_params)
        print(cmd)
        os.system(cmd)
    
def build_cmd(lattice_params, run_params=None, storage_params=None, pbs_params=None):
    """
    Builds a command to lauch a stream using a series of positional arguments.
    Positional arguments are ugly, but bash lacks built-in support for 
    named arguments longer than a single character.
    
    The order of the arguments is:
    1)  nx
    2)  nt
    3)  beta
    4)  k4
    5)  k6
    6)  exec
    7)  configs_to_run
    8)  config_limit
    9)  nstep2
    10) nstep1
    11) rootstore         
    12) A, i.e., the PBS option for the allocation name
    13) N, i.e., the PBS option for the stream name
    """ 

    if run_params is None:
        ## By default, run phi-algorithm for 10 configurations = 100 trajectories
        run_params = {
            'nstep2':30,
            'nstep1':1,
            'configs_to_run':4,
            'config_limit':10,
            'exec':'su4_mrep_phi_bc1_mvapich_wj',
            #'exec':'su4_mrep_hmc_bc1_mvapich_wj',
            }

    if storage_params is None:    
        storage_params = {
            'rootstore':'/lqcdproj/multirep/wjay/Run_SU4_Nf2_Nas2_{nx}{nt}'.format(**lattice_params),
            }

    if pbs_params is None:
        k4 = lattice_params['k4'].split('.')[-1]
        k6 = lattice_params['k6'].split('.')[-1]
        b  = ''.join(lattice_params['beta'].split('.'))
        stream_name = 'g'+'_'.join([b,k4,k6])
        pbs_params = {
            'A' : 'multirep',
            'N' : stream_name,
            }
    ## Positinal arguments
    args = '{nx} {nt} {beta} {k4} {k6} '.format(**lattice_params)
    args+= '{exec} {configs_to_run} {config_limit} {nstep2} {nstep1} '.format(**run_params)
    args+= '{rootstore} '.format(**storage_params)
    args+= '{A} {N}'.format(**pbs_params)

    ## The command itself
#    cmd_local  = "/lqcdproj/multirep/wjay/Run_SU4_Nf2_Nas2_1632/run_gauge.sh "
#    cmd_local += args
#    return cmd_local

    cmd  = "qsub -A {A} -N {N} /lqcdproj/multirep/wjay/Run_SU4_Nf2_Nas2_1632/run_gauge.sh ".format(**pbs_params)
    cmd += '-F "' + args + '"' 
    return cmd

if __name__ == '__main__':
    main()
    
    
    
