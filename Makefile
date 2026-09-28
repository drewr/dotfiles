.PHONY: install home update news

install:
	zsh install

home: install
	zsh build-home-manager

update:
	nix flake update --flake d/.config/home-manager

# Derive the current machine's Home Manager config name (username@system) the
# same way build-home-manager does, then pass it explicitly. `home-manager news`
# otherwise resolves by `$USER`/`$USER@hostname`, which doesn't match the
# `<user>@<system-triple>` names in this repo's flake.
news:
	@username="$${LOGNAME:-$$(whoami)}"; \
	system="$$(uname -mo)"; \
	case "$$system" in \
	  "arm64 Darwin"|"Darwin arm64") arch="aarch64-darwin" ;; \
	  "x86_64 GNU/Linux")            arch="x86_64-linux" ;; \
	  *)                             arch="aarch64-linux" ;; \
	esac; \
	cd "$$HOME/.config/home-manager" || exit 1; \
	home-manager news --flake ".#$${username}@$${arch}"
