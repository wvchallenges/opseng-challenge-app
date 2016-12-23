# Wave Challenge Submission
This repo creates all the infrastructure necessary to host the Python app.py app

## What's Created
- Bastion instance (on public subnet) exclusive to this app. Travis modifies the sec_grp to run ansible playbooks through it.

- Private instance (on private subnet) that hosts the app. 
   - Install requirements from requirements.txt using PIP
   - Clone MASTER HEAD of original repo
   - Install Nginx and use as proxy. Listen on port 80. Proxy to port 8000.
   - Gunicorn as Upstart service. Serve on port 8000.

- An Elastic Load Balancer that listens on 80 and serves on 80. Helps keep private instance from attacks.

## Setup
- Git repo hooked to Travis CI so every push and PR is built automatically.
- Travis has been configured to act as the trigger for infrastructure creation.
- Bash and Ansible scripts create infrastructure, from scratch to a fully hosted app.

- Pulling this repo's contents into the original repository will help create a pipeline for the app using Travis.
- One may need to manually setup Travis once to hook it up to the main repository.
- Once pulled, when a new commit is pushed to the branch, Travis picks up the commit and builds it, and the changes are pushed to the private instance automatically during the build.

## Notes
- aws-app.sh is designed to only return the ELB's DNS endpoint. It is left to Travis to create the necessary infrastructure. 
- Plans were to also be able to spin-up infra using aws-app.sh but the differences between MacOS X and Travis' build environment meant giving up on the idea (was partially built but later torn down to resort to a simple aws-app.sh file)
- It is assumed that the keypair "svaranasi-kp" is already created in the AWS account. It would have made it harder to distribute a freshly created KP between the scripts.
- Ansible 2.0.2.0 was used for convenience and previous working knowledge. Much has changed with Ansible since then.
- Amazon Linux was used to keep things simple and stable. The other obvious choice would have been Ubuntu 16.04. 
