#! /bin/bash

## This script is used to produce AOD files from a gridpack for
## 2017 data. The CMSSW version is 10_6_X and all four lifetimes are

## Usage: ./runOffGridpack.sh gridpack_file.tar.xz

#For lxplus
# export X509_USER_PROXY=$1
# voms-proxy-info -all
# voms-proxy-info -all -file $1
set -e
export BASEDIR=`pwd`
GP_f=$1
echo "${BASEDIR}"
echo "${GP_f}"
GRIDPACKDIR=${BASEDIR}/gridpacks/Production
LHEDIR=${BASEDIR}/lhes
SAMPLEDIR=${BASEDIR}/samples
[ -d ${LHEDIR} ] || mkdir ${LHEDIR}

HADRONIZER="externalLHEProducer_and_PYTHIA8_Hadronizer"
namebase=${GP_f/.tar.xz/}
echo "${namebase}"
#nevent=1000
nevent=3
amass=$2
HTBin=$3


export VO_CMS_SW_DIR=/cvmfs/cms.cern.ch
source $VO_CMS_SW_DIR/cmsset_default.sh

## Loading the latest CMSSW version in consistent with 
export SCRAM_ARCH=slc7_amd64_gcc820

if ! [ -r CMSSW_10_6_26/src ] ; then
    scram p CMSSW CMSSW_10_6_26
fi
cd CMSSW_10_6_26/src
eval `scram runtime -sh`
scram b -j 4

xrdcp root://cmseos.fnal.gov//eos/uscms/store/user/nbower/GenerationTools/SUSYGluGluToHToAA_AToBB_AToTauTau_M-12_FilterTauTauTrigger_TuneCP5_13TeV_madgraph_pythia8_cff.py    ./
xrdcp root://cmseos.fnal.gov//eos/uscms/store/user/nbower/GenerationTools/Generator_Add_Random.py   ./
xrdcp root://cmseos.fnal.gov//eos/uscms/store/user/nbower/gridPacks/ggh01_M125_Toa01a01_M12_Tobbtautau_slc6_amd64_gcc630_CMSSW_9_3_16_tarball.tar.xz   ./
xrdcp root://cmseos.fnal.gov//eos/uscms/store/user/nbower/GenerationTools/Select_PileUp.py   ./
xrdcp root://cmseos.fnal.gov//eos/uscms/store/user/nbower/GenerationTools/PU_FileList.txt   ./


ls -lrth



mkdir -p Configuration/GenProduction/python/
cp SUSYGluGluToHToAA_AToBB_AToTauTau_M-12_FilterTauTauTrigger_TuneCP5_13TeV_madgraph_pythia8_cff.py Configuration/GenProduction/python/.
pwd
eval `scram runtime -sh`
scram b -j 4
echo "0.) Generating GEN for a mass ${amass}"
genfragment=${namebase}_GEN_cfg_${amass}.py
#sed -i "s/TCP_m_REPLACEME_w_1_htj_REPLACEME/TCP_m_${amass}_w_1_htj_${HTBin}/g" Configuration/GenProduction/python/DYJetsToLL_M-1to10_HTbinned_TuneCP5_13TeV-madgraphMLM-pythia8_cff.py

cmsDriver.py Configuration/GenProduction/python/SUSYGluGluToHToAA_AToBB_AToTauTau_M-12_FilterTauTauTrigger_TuneCP5_13TeV_madgraph_pythia8_cff.py       \
    --fileout file:${namebase}_${amass}_GEN.root         \
    --mc --eventcontent RAWSIM --datatier GEN --conditions 102X_upgrade2018_realistic_v15         \
    --beamspot Realistic25ns13TeVEarly2018Collision --step LHE,GEN      \
    --geometry DB:Extended --era Run2_2018         \
    --python_filename ${genfragment} -n ${nevent} --no_exec
##Modify cmsDriver command with the latest conditions consistent with 
python Generator_Add_Random.py ${genfragment}



#Make each file unique to make later publication possible


cmsRun -p ${genfragment}

# Step1 is pre-computed, since it takes a while to load all pileup pre-mixed samples
echo "1.) Generating SIM for a mass ${amass}"
cmsDriver.py step2 --filein file:${namebase}_${amass}_GEN.root --fileout file:${namebase}_${amass}_SIM.root        \
    --mc --eventcontent RAWSIM --runUnscheduled --datatier GEN-SIM --conditions 102X_upgrade2018_realistic_v15 --beamspot Realistic25ns13TeVEarly2018Collision --step SIM         \
    --nThreads 8 --geometry DB:Extended --era Run2_2018 --python_filename ${namebase}_${amass}_SIM_cfg.py -n  ${nevent} --no_exec  


cmsRun -p ${namebase}_${amass}_SIM_cfg.py 
PUFILE=$(python Select_PileUp.py)

echo "2.) Generating DIGI(premix) for a mass ${amass}" 
cmsDriver.py step3 \
    --filein file:${namebase}_${amass}_SIM.root --fileout file:${namebase}_${amass}_DIGIPremix.root \
    --pileup_input "${PUFILE}" \
    --mc --eventcontent PREMIXRAW --runUnscheduled --datatier GEN-SIM-DIGI --conditions 102X_upgrade2018_realistic_v15 --step DIGI,DATAMIX,L1,DIGI2RAW \
    --procModifiers premix_stage2 --nThreads 8 --geometry DB:Extended --datamix PreMix --era Run2_2018 --python_filename ${namebase}_${amass}_DIGIPremix_cfg.py -n ${nevent} --no_exec     


rm ${namebase}_${amass}_GEN.root 

cmsRun -p  ${namebase}_${amass}_DIGIPremix_cfg.py

ls
echo "3.) Generating HLT for a mass ${amass} in new CMSSW"
rm ${namebase}_${amass}_SIM.root 
cd ../../.
export SCRAM_ARCH=slc7_amd64_gcc630
if ! [ -r CMSSW_9_4_14_UL_patch1/src ] ; then
    scram p CMSSW_9_4_14_UL_patch1   
fi
mv CMSSW_10_6_26/src/${namebase}_${amass}_DIGIPremix.root CMSSW_9_4_14_UL_patch1/src/.  

cd CMSSW_9_4_14_UL_patch1/src/
ls
eval `scram runtime -sh`

cmsDriver.py step4 --filein file:${namebase}_${amass}_DIGIPremix.root --fileout file:${namebase}_${amass}_HLT.root --mc --eventcontent RAWSIM \
--datatier GEN-SIM-RAW --conditions 94X_upgrade2018_realistic_v15 --customise_commands 'process.source.bypassVersionCheck = cms.untracked.bool(True)' \
--step HLT:2e34v40 --nThreads 8 --geometry DB:Extended --era Run2_2018 --python_filename ${namebase}_${amass}_HLT_cfg.py -n ${nevent} --no_exec


cmsRun -p  ${namebase}_${amass}_HLT_cfg.py




cd ../../.

echo "4.) Generating RECO for a mass ${amass} in previous CMSSW"

export SCRAM_ARCH=slc7_amd64_gcc820
if ! [ -r CMSSW_10_6_26/src ] ; then
    scram p CMSSW CMSSW_10_6_26
fi
mv CMSSW_9_4_14_UL_patch1/src/${namebase}_${amass}_HLT.root CMSSW_10_6_26/src/. 
rm -rf CMSSW_9_4_14_UL_patch1/
cd CMSSW_10_6_26/src/
eval `scram runtime -sh`
cmsDriver.py step5 --filein file:${namebase}_${amass}_HLT.root --fileout file:${namebase}_${amass}_recoAOD.root  \
 --mc --eventcontent AODSIM --runUnscheduled --datatier AODSIM --conditions 102X_upgrade2018_realistic_v15 --step RAW2DIGI,L1Reco,RECO,RECOSIM --nThreads 8 --geometry DB:Extended \
 --era Run2_2018 --python_filename ${namebase}_${amass}_recoAOD_cfg.py -n ${nevent} --no_exec
cmsRun -p  ${namebase}_${amass}_recoAOD_cfg.py
rm ${namebase}_${amass}_HLT.root
cmsDriver.py --python_filename ${namebase}_${amass}_MINIAOD_cfg.py --eventcontent MINIAODSIM --customise Configuration/DataProcessing/Utils.addMonitoring \
--datatier MINIAODSIM --fileout file:${namebase}_${amass}_MINIAOD.root --conditions 102X_upgrade2018_realistic_v15 --step PAT --procModifiers run2_miniAOD_UL \
--geometry DB:Extended --filein file:${namebase}_${amass}_recoAOD.root --era Run2_2018,run2_miniAOD_devel --runUnscheduled --no_exec --mc -n ${nevent} 
cmsRun -p ${namebase}_${amass}_MINIAOD_cfg.py

xrdcp ${namebase}_${amass}_MINIAOD.root root://cmseos.fnal.gov//eos/uscms/store/user/nbower/Events/2018_SUSYGluGluToHToAA_AToBB_AToTauTau_M-12_FilterTauTauTrigger_TuneCP5_13TeV_madgraph_pythia8_MINIAOD/SUSYGluGluToHToAA_AToBB_AToTauTau_M-12_FilterTauTauTrigger_TuneCP5_13TeV_madgraph_pythia8_MINIAOD_${namebase}.root
#cp ${namebase}_${amass}_recoAOD.root ../../.
pwd
cmd="ls -arlth *.root"
echo $cmd && eval $cmd
cd ../../.
rm -rf CMS*

echo "DONE."
echo "ALL Done"