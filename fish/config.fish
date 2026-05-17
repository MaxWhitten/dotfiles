if status is-interactive
# Commands to run in interactive sessions can go here
end

set -g fish_greeting ""

set -Ux EDITOR /usr/bin/nano
set -Ux VISUAL /usr/bin/nano

source ~/.config/fish/theme.fish

source ~/.config/fish/functions/*

alias ll='ls -lah'
alias c='clear'
alias cls='clear'
alias p1ng='ping -c 4 1.1.1.1'
alias chmac='sudo ip link set dev wlan0 down; and sudo macchanger -r wlan0; and sudo ip link set dev wlan0 up'
alias notes='nano -0 notes'
alias hidle='~/.config/hypr/toggle-hypridle'

starship init fish | source

# Created by `pipx` on 2026-02-20 17:40:02
set PATH $PATH /home/eclypse/.local/bin
