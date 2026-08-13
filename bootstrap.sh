#!/usr/bin/env bash
set -e

main() {
    GITHUB_USER="talife"
    GIT_DIR="$HOME/git"

    echo "🚀 Starting the ultimate bootstrap process..."

    # Detect if we are running inside Windows Subsystem for Linux
    IS_WSL=false
    if grep -qE "(Microsoft|WSL)" /proc/version &> /dev/null; then
        IS_WSL=true
        echo "🪟 WSL Environment Detected!"
    else
        echo "🐧 Native Linux Environment Detected!"
    fi

    # 1. Ask for sudo password upfront
    sudo -v

    # 2. Sync Windows Root CA Store to WSL (Fixes Cloudflare / Corporate Proxy SSL)

    if [ "$IS_WSL" = true ]; then
        echo "🔐 Synchronizing Windows Root Certificate Authority (CA) store to WSL..."
        mkdir -p /tmp/windows-root-certs
        WIN_CERT_DIR=$(wslpath -w /tmp/windows-root-certs)

        powershell.exe -NoProfile -Command '
        $certDir = "'"$WIN_CERT_DIR"'"
        Get-ChildItem -Path Cert:\LocalMachine\Root, Cert:\CurrentUser\Root | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] } | ForEach-Object {
            $certText = [System.Convert]::ToBase64String($_.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert), [System.Base64FormattingOptions]::InsertLineBreaks)
            $pem = "-----BEGIN CERTIFICATE-----`r`n$certText`r`n-----END CERTIFICATE-----"
            $filePath = Join-Path -Path $certDir -ChildPath "$($_.Thumbprint).crt"
            [System.IO.File]::WriteAllText($filePath, $pem, [System.Text.Encoding]::ASCII)
        }
        ' > /dev/null 2>&1

        sudo cp /tmp/windows-root-certs/*.crt /usr/local/share/ca-certificates/
        sudo update-ca-certificates --fresh > /dev/null 2>&1
        rm -rf /tmp/windows-root-certs
        echo "✅ Certificate trust store updated successfully!"
    else
        echo "✅ Skipping Windows CA sync (Native Linux environment)."
    fi

    # 3. Install core prerequisites (ADDED: stow and zsh so we can symlink dotfiles before Ansible runs!)
    echo "📦 Installing prerequisites..."
    sudo apt-get update
    sudo apt-get install -y git software-properties-common curl stow zsh

    # Create lightweight native Windows browser wrapper for all standard Linux browser commands
    if [ ! -f /usr/local/bin/wslview ]; then
        echo "🌐 Creating lightweight native Windows browser wrappers..."
        sudo tee /usr/local/bin/wslview > /dev/null << 'EOF'
#!/bin/sh
exec cmd.exe /c start "$@"
EOF
        sudo chmod +x /usr/local/bin/wslview

        # Symlink standard Linux browser openers directly to our Windows forwarder
        for browser_cmd in xdg-open x-www-browser www-browser; do
            sudo ln -sf /usr/local/bin/wslview "/usr/local/bin/$browser_cmd"
        done
    fi

    # Add Ansible PPA and install
    if ! command -v ansible &> /dev/null; then
        sudo apt-add-repository --yes --update ppa:ansible/ansible
        sudo apt-get install -y ansible
    fi

    # Install GitHub CLI
    if ! command -v gh &> /dev/null; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update && sudo apt install gh -y
    fi

    # 4. Authenticate with GitHub (Requires both Auth and SSH Signing scopes!)
    echo "🔐 Checking GitHub authentication status and scopes..."
    # Capture the status output (using || true to prevent the script from exiting if not logged in)
    AUTH_STATUS=$(gh auth status 2>&1 || true)

    # Check if either scope is missing
    if ! echo "$AUTH_STATUS" | grep -q "admin:public_key" || ! echo "$AUTH_STATUS" | grep -q "admin:ssh_signing_key"; then
        echo "🌐 Not logged in or missing required scopes. Opening browser for authentication..."
        gh auth login -w -s admin:public_key -s admin:ssh_signing_key
    else
        echo "✅ Already authenticated with all required scopes! Skipping login..."
    fi

    # 5. Generate & Upload SSH key (ONLY if key doesn't exist locally/remotely!)
    ENV_PREFIX=$([ "$IS_WSL" = true ] && echo "WSL" || echo "Linux")
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        echo "🔑 Generating fresh SSH key..."
        ssh-keygen -t ed25519 -C "${ENV_PREFIX}-$(hostname)-$(date +%F)" -f ~/.ssh/id_ed25519 -N ""
    else
        echo "✅ Local SSH key already exists! Skipping generation..."
    fi

    # Check if this exact public key is already registered on your GitHub account
    PUB_KEY_CONTENT=$(cat ~/.ssh/id_ed25519.pub)
    # Upload for Authentication
    if ! gh ssh-key list | grep "$PUB_KEY_CONTENT" | grep -q -i "authentication"; then
        echo "☁️ Uploading SSH key to GitHub for Authentication..."
        gh ssh-key add ~/.ssh/id_ed25519.pub --title "${ENV_PREFIX}-$(hostname)-Auth" --type authentication
    else
        echo "✅ Authentication key is already registered on GitHub!"
    fi

    # Upload for Commit Signing
    if ! gh ssh-key list | grep "$PUB_KEY_CONTENT" | grep -q -i "signing"; then
        echo "✍️ Uploading SSH key to GitHub for Commit Signing..."
        gh ssh-key add ~/.ssh/id_ed25519.pub --title "${ENV_PREFIX}-$(hostname)-Signing" --type signing
    else
        echo "✅ Signing key is already registered on GitHub!"
    fi

    # 6. Create the target Git directory
    mkdir -p "$GIT_DIR"

    # 7. Clone all three repositories (ansible, .dotfiles, and install-home) via SSH!
    echo "📥 Cloning repositories..."
    for repo in ansible .dotfiles install-home; do
        if [ ! -d "$GIT_DIR/$repo" ]; then
            echo "⬇️ Cloning $repo..."
            git clone "git@github.com:$GITHUB_USER/$repo.git" "$GIT_DIR/$repo"
        else
            echo "✅ $repo repo already exists, pulling latest..."
            git -C "$GIT_DIR/$repo" pull
        fi
    done

    # 8. Run your Stow installation script FIRST so dotfiles are linked before OMZ/TPM run!
    echo "🔗 Symlinking dotfiles..."
    cd "$GIT_DIR/.dotfiles"
    chmod +x ubuntu install clean-env
    for file in "$HOME/.zshrc" "$HOME/.tmux.conf" "$HOME/.zsh_profile"; do
        if [ -f "$file" ] && [ ! -L "$file" ]; then
            echo "🧹 Backing up pre-existing default file: $file -> $file.bak"
            mv "$file" "$file.bak"
        fi
    done
    ./ubuntu

    # 9. Execute the Ansible Playbook via install-home runner SECOND!
    echo "⚙️ Running Ansible playbook..."
    cd "$GIT_DIR/install-home/playbook"
    chmod +x run.sh
    ./run.sh

    echo "🎉 Bootstrap complete! Close this terminal and open a new one to launch into Zsh."
}

# Execute the main function
main "$@"
