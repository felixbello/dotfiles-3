# Create a new directory and enter it
mkcd() {
    mkdir -p "$@" && cd "$_" || exit;
}

# cd into directory with fzf
fcd() {
    local dir
    dir=$(find "${1:-.}" -path '*/\.*' -prune \
        -o -type d -print 2> /dev/null | fzf +m) &&
    cd "$dir" || exit
}

# Checkout branches or tags with fzf
fco() {
    local tags branches target
    tags=$(
        git tag | awk '{print "\x1b[31;1mtag\x1b[m\t" $1}') || return
    branches=$(
        git branch --all | grep -v HEAD             |
        sed "s/.* //"    | sed "s#remotes/[^/]*/##" |
        sort -u          | awk '{print "\x1b[34;1mbranch\x1b[m\t" $1}') || return
    target=$(
        (echo "$tags"; echo "$branches") |
        fzf-tmux -l30 -- --no-hscroll --ansi +m -d "\t" -n 2) || return
    git checkout "$(echo "$target" | awk '{print $2}')"
}

# fkill - kill process
fkill() {
    local pid
    if [ "$UID" != "0" ]; then
        pid=$(ps -f -u $UID | sed 1d | fzf -m | awk '{print $2}')
    else
        pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
    fi

    if [ "x$pid" != "x" ]
    then
        echo "$pid" | xargs kill "-${1:-9}"
    fi
}

# fshow - git commit browser
fshow() {
    git log --graph --color=always \
        --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" |
    fzf --ansi --no-sort --reverse --tiebreak=index --bind=ctrl-s:toggle-sort \
        --bind "ctrl-m:execute:
            (grep -o '[a-f0-9]\{7\}' | head -1 |
            xargs -I % sh -c 'git show --color=always % | less -R') << 'FZF-EOF'
            {}
FZF-EOF"
}

# Open tmux and Vim in an IDE like layout
ide() {
    if [ -n "$1" ]; then
        cd "$1" || exit
    fi

    if [ -z "${TMUX}" ]; then
        tmux new-session -d -s ide
        tmux split-window -vb -p 90
        tmux select-pane -t 0
        tmux send-keys 'nvim +NERDTree' C-m
    else
        tmux split-window -vb -p 90
        tmux select-pane -t 0
        tmux send-keys 'nvim +NERDTree' C-m
    fi
}

# Update project dependencies
depu() {
    # Git submodules
    if [ -e .gitmodules ]; then
        printf "Updating Git submodules for %s...\n\n" "${PWD##*/}"
        git submodule update --init
    fi

    # npm
    if [ -e package-lock.json ]; then
        printf "Updating npm dependencies for %s...\n\n" "${PWD##*/}"
        npm install
        npm update
        npm outdated
    fi

    # Go
    if [ -e go.mod ]; then
        printf "Updating Go dependencies for %s...\n\n" "${PWD##*/}"
        go get -u -t all
        go mod tidy
    fi

    # Rust
    if [ -e Cargo.toml ]; then
        printf "Updating Cargo dependencies for %s...\n\n" "${PWD##*/}"
        cargo update
    fi
}

# System update
pacu() {
    processes=()

    # Dotfiles repo
    printf '\e[1mUpdating dotfiles repo\e[0m\n'
    (cd "${HOME}/dotfiles" && git pull)

    # System tools
    case "$(uname)" in
    # On Linux, use the respective package manager
    'Linux')
        # Arch Linux
        if [ -x "$(command -v pacman)" ]; then
            printf '\e[1mUpdating pacman packages\e[0m\n'
            sudo pacman -Syu --noconfirm
            orphans=$(sudo pacman -Qtdq) || orphans=''
            if [ -n "${orphans}" ]; then
                sudo pacman -Rns $orphans --noconfirm
            fi
            sudo pacman -Sc --noconfirm
        fi
        if [ -x "$(command -v yay)" ]; then
            printf '\e[1mUpdating Yay packages\e[0m\n'
            yay -Syua --noconfirm
        fi
        if [ -x "$(command -v paccache)" ]; then
            printf '\e[1mCleaning Pacman cache\e[0m\n'
            sudo paccache -r
        fi
        if [ -x "$(command -v pacdiff)" ]; then
            printf '\e[1mChecking for Pacman maintenance issues\e[0m\n'
            sudo DIFFPROG="${EDITOR} -d" pacdiff
        fi
        # Solus
        if [ -x "$(command -v eopkg)" ]; then
            printf '\e[1mUpdating eopkg packages\e[0m\n'
            sudo eopkg upgrade
        fi
        # Debian
        if [ -x "$(command -v apt)" ]; then
            printf '\e[1mUpdating apt packages\e[0m\n'
            sudo apt update
            sudo apt full-upgrade --yes
            sudo apt autoremove --yes
        fi
        # Firmwares
        if [ -x "$(command -v fwupdmgr)" ]; then
            printf '\e[1mUpdating firmwares\e[0m\n'
            fwupdmgr refresh
            fwupdmgr update
        fi
        ;;

    # On macOS, use mas and Homebrew
    'Darwin')
        if [ -x "$(command -v mas)" ]; then
            printf '\e[1mUpdating App Store apps\e[0m\n'
            mas upgrade
        fi
        if [ -x "$(command -v brew)" ]; then
            printf '\e[1mUpdating Homebrew packages\e[0m\n'
            brew update
            brew upgrade
            cat ~/dotfiles/*Brewfile | brew bundle --file=-
            cat ~/dotfiles/*Brewfile | brew bundle cleanup --force --file=-
            brew cu --all --yes --cleanup
            brew cleanup --prune 7
        fi
        if typeset -f zprezto-update > /dev/null; then
            printf '\e[1mUpdating zprezto\e[0m\n'
            zprezto-update &
            processes+=("$!")
        fi
        ;;
    esac

    # Go
    if [ -x "$(command -v go)" ]; then
        printf '\e[1mUpdating Go binaries\e[0m\n'
        ("${HOME}/dotfiles/update-go.sh") &
        processes+=("$!")
    fi

    # Rust
    if [ -x "$(command -v rustup)" ]; then
        printf '\e[1mUpdating rustup components\e[0m\n'
        (rustup update) &
        processes+=("$!")
    fi

    # npm
    if [ -x "$(command -v npm)" ]; then
        printf '\e[1mUpdating globally installed npm packages\e[0m\n'
        npm update -g

        printf '\e[1mUpdating Node.js projects\e[0m\n'
        ("${HOME}/dotfiles/update-js.sh") &
        processes+=("$!")
    fi

    # Yarn
    if [ -x "$(command -v yarn)" ]; then
        printf '\e[1mUpdating globally installed Yarn packages\e[0m\n'
        (yarn global upgrade > /dev/null) &
        processes+=("$!")
    fi

    # Python pip
    if [ -x "$(command -v pip)" ]; then
        printf '\e[1mUpdating pip packages\e[0m\n'
        (pip list --user --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1  | xargs -n1 pip install --user --upgrade) &
        processes+=("$!")
    fi

    # NeoVim
    if [ -x "$(command -v nvim)" ]; then
        printf '\e[1mUpdating Vim plugins\e[0m\n'
        nvim --headless -c 'PlugUpgrade | PlugClean! | PlugUpdate | qa'
        nvim --headless -c 'UpdateRemotePlugins | qa'
    fi

    # Wait for all processes to finish
    for p in ${processes[*]}; do
        wait "$p"
    done

    printf '\e[1mSystem update finished\e[0m\n'
}
