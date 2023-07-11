#!/bin/bash

# Function to install smallstep package
install_smallstep() {
    echo "Installing smallstep..."
    curl -LO https://smallstep.com/cli/install && chmod 755 install && sudo ./install
}

# Function to install linkerd CLI
install_linkerd() {
    echo "Installing linkerd CLI..."
    curl -sL https://run.linkerd.io/install | sh
    export PATH=$PATH:$HOME/.linkerd2/bin
    echo 'export PATH=$PATH:$HOME/.linkerd2/bin' >> ~/.bashrc
}

# Function to install kubectl
install_kubectl() {
    echo "Installing kubectl..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubectl
}

# Function to install doctl
install_doctl() {
    echo "Installing doctl..."
    sudo snap install doctl --classic
}

# Detect the operating system
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    install_smallstep
    install_linkerd
    install_kubectl
    install_doctl
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    install_smallstep
    install_linkerd
    brew install kubectl
    brew install doctl
else
    echo "Unsupported operating system."
    exit 1
fi

echo "Package installation completed."
