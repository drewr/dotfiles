.PHONY: install home

install:
	zsh install

home: install
	zsh build-home-manager
