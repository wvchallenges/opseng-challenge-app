#!/bin/bash
#### Wave Ops Challenge
####
####

#set -o errexit
#set -o pipefail


virtualenv  -p python2.7 waveansible

source waveansible/bin/activate

pip -q install ansible
pip -q install boto

ansible-vault decrypt  env/secrets.yml --vault-password-file env/notgood.txt

source env/secrets.yml

echo "Starting AWS setup ...."

ansible-playbook --tag aws   playbook.yml 


new_instance_ip=$(aws ec2 describe-instances --filters Name=tag:Name,Values=wsoyinka-waveapp --output text --query 'Reservations[*].Instances[*].PublicIpAddress')


## Forcefully bootstrap 16.04 LTS ami

#ssh -i "./wsoyinka-opseng-challenge-key.pem" -o StrictHostKeyChecking=no  ubuntu@$new_instance_ip  "sudo apt-get -y update && sudo dpkg --configure -a  && sudo apt-get -q -y install python2.7 && sudo ln  -s /usr/bin/python2.7 /usr/bin/python" 

echo "Did I get here at all ?"

ssh -v -i ./wsoyinka-opseng-challenge-key.pem -o StrictHostKeyChecking=no  ubuntu@$new_instance_ip  "sudo apt-get -y update && sudo dpkg --configure -a"  

echo "Or even here at all ?? "

ssh -v -i ./wsoyinka-opseng-challenge-key.pem -o StrictHostKeyChecking=no  ubuntu@$new_instance_ip  "sudo apt-get -q -y install python2.7"

ssh -v -i ./wsoyinka-opseng-challenge-key.pem -o StrictHostKeyChecking=no  ubuntu@$new_instance_ip  "sudo ln  -s /usr/bin/python2.7 /usr/bin/python" 


ansible-playbook --tag common,nginx,deploy   playbook.yml 

ansible-vault encrypt  env/secrets.yml --vault-password-file env/notgood.txt

echo  "The website can be reached at:"

echo ""

echo  "http://$new_instance_ip " 

echo ""

echo " We are working on a more PCI DSS compliant version of the site...because we care about  wave customer data. Coming soon and can be reached here:"

echo ""

echo  "https://$new_instance_ip"

echo ""
echo ""
echo ""
