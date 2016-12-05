Solution: Deployment Automation for Wave Ops Engineering Development Challenge 
======

Various technologies, stacks and hacks were used for this task. Some of them are:

* Linux (Ubuntu 16.04.1 LTS - http://kernel.org and http://ubuntu.com) 

* Bash (of course :-)

* nginx (https://www.nginx.com/)

* openssl (https://www.openssl.org/)

* supervisord (http://supervisord.org/)

* ssh (http://openssh.org )

* python ()

*  boto ()

* ansible (https://www.ansible.com/)

* gunicorn (http://gunicorn.org)

* Amazon Web Service ()

* EC2

* VPC 

* IAM 

* aws-cli tools 


To get started, download and excute the aws-app.sh script in a suitable location on your filesystem.

```
$ wget https://github.com/wsoyinka/opseng-challenge-app/blob/master/aws-app.sh
$ ./aws-app.sh
$ <Supply the password provided to decrypt sentsive information required for this process >
```

# CHALLENGES

A few [minor] speedbumps were encountered in cobbling together this solution. Some were:

* Delibrate choice of OS version (Ubuntu 16.04 LTS)

* Improperly documentated changes/regressions in the internals of some of the major components

* Opaqueness of data structures in some of the bleeding edge ansible modules needed

# SOLUTIONS


# FUN FACTS
