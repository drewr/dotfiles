FROM colinsurprenant/ubuntu-raring-amd64

RUN apt-get install -y software-properties-common
RUN add-apt-repository "deb http://us.archive.ubuntu.com/ubuntu/ raring restricted universe multiverse"
RUN add-apt-repository "deb http://us.archive.ubuntu.com/ubuntu/ raring-updates main restricted"
RUN add-apt-repository "deb http://us.archive.ubuntu.com/ubuntu/ raring-backports main restricted universe multiverse"
RUN apt-get update
RUN apt-get install -y aptitude djbdns curl git zsh 
RUN curl -sO http://apt.puppetlabs.com/puppetlabs-release-raring.deb
RUN dpkg -i puppetlabs-release-raring.deb
RUN add-apt-repository ppa:webupd8team/java
RUN apt-get update
RUN apt-get install -y puppet

