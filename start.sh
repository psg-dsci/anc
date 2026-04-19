#!/bin/bash
cd /home/ec2-user/app

sudo yum install python3 -y
pip3 install flask

pkill -f app.py || true

nohup python3 app.py &
