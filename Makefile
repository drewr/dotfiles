.PHONY: install home update

install:
	zsh install

home: install
	zsh build-home-manager

update:
	nix flake update --flake d/.config/home-manager
