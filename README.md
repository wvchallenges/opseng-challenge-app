# Wave Challenge Submission By Sanjay Varanasi
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
- One may need to manually setup Travis once to hook it up to the original repository.
- Once pulled, when a new commit is pushed to the branch, the changes are pushed to the private instance automatically by the end of the build.

## Notes
- aws-app.sh is designed to only return the ELB's DNS endpoint. It is left to Travis to create the necessary infrastructure. 
- Plans were to also be able to spin-up infra using aws-app.sh but the differences between MacOS X and Travis' build environment meant I had to give up on that idea. That would have been very cool.

