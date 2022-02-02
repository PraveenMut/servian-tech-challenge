#!/bin/bash

# anti-fragility checks

set -euo pipefail

DEPS=(
      "go"
      "git"
)

for d in ${DEPS[@]}
do 
      which "${d}" > /dev/null || (echo "dependency ${d} not found" | tee -a log; exit 1)
done

cd $HOME
echo "Downloading rice dep.." | tee -a ~/log
PATH=$PATH go get github.com/GeertJohan/go.rice/rice
echo "Moving to Path..." | tee -a ~/log
sudo mv ~/go/bin/rice /usr/local/bin
echo "Cloning Repo..."  | tee -a ~/log
PATH=$PATH git clone https://github.com/servian/TechChallengeApp.git
cd TechChallengeApp
echo "Build app" | tee -a ~/log
./build.sh
echo "Download cloud_sql_proxy" | tee -a ~/log
curl -L https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -o ../cloud_sql_proxy
echo "Changing permissions and moving" | tee -a ~/log
chmod +x ../cloud_sql_proxy
sudo mv ../cloud_sql_proxy /usr/local/bin
echo "Starting up the Cloud SQL Proxy" | tee -a ~/log
cloud_sql_proxy -instances=servian-gtd-application:australia-southeast1:gtd-db=tcp:5432 &
echo "Waiting 30 seconds for to ensure that secure tunnel has been initiated" | tee -a ~/log
sleep 30
echo "Seeding DB.." | tee -a ~/log
./dist/TechChallengeApp updatedb -s
echo "MISSION ACCOMPLISHED! *sweeping game credits*" | tee -a ~/log 