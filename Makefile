install: /etc/iptables/rules.v4
	cp zshrc ${HOME}/.zshrc
	cp zshenv ${HOME}/.zshenv
	if [ ! -d ${HOME}/.zsh.d ]; then mkdir ${HOME}/.zsh.d; fi
	( cd zsh.d; tar cf - . ) | ( cd ${HOME}/.zsh.d; tar xf - )
	( cd d; tar cf - . ) | ( cd $(HOME); tar xf - )
	( cd root; tar cf - . ) | ( cd /; sudo tar xf - )
	sudo iptables-restore </etc/iptables/rules.v4


