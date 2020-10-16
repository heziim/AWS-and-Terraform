#!/bin/bash
sudo yum install -y nginx
sudo echo 'OpsSchool Rules' | sudo tee  /usr/share/nginx/html/index.html
sudo systemctl restart nginx
