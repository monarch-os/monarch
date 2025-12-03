#!/bin/bash
set -e

# Configuration inspired by p3ta00's and 3akev's exegol configuration
# https://github.com/p3ta00/p3ta_exegol/
# https://github.com/3akev/exegol-resources

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

BIN_DIR="/opt/my-resources/bin"
SETUP_DIR="/opt/my-resources/setup"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Loading Custom User Setup (Fast Mode)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"

echo -e "${BLUE}[*]${NC} Installing Kitty..."
apt update && apt install -y kitty
echo -e "${GREEN}[✓]${NC} Kitty installed"

if [ ! -f "$BIN_DIR/starship" ]; then
    echo -e "${BLUE}[*]${NC} Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y --bin-dir="$BIN_DIR"
    echo -e "${GREEN}[✓]${NC} Starship installed"
fi

if [ -f "$SETUP_DIR/starship/starship.toml" ] && [ ! -f /root/.config/starship.toml ]; then
    mkdir -p /root/.config
    cp "$SETUP_DIR/starship/starship.toml" /root/.config/starship.toml
    echo -e "${GREEN}[✓]${NC} Starship config installed"
fi

# ───────────────────────────────────────────────────────────────────
# Install Zellij (precompiled)
# ───────────────────────────────────────────────────────────────────

if [ ! -f "$BIN_DIR/zellij" ]; then
    echo -e "${BLUE}[*]${NC} Installing Zellij..."
    curl -sL https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz | tar -xz -C "$BIN_DIR"
    chmod +x "$BIN_DIR/zellij"
    echo -e "${GREEN}[✓]${NC} Zellij installed"
fi

if [ -d "$SETUP_DIR/zellij" ] && [ ! -d /root/.config/zellij ]; then
    mkdir -p /root/.config/zellij
    cp -r "$SETUP_DIR/zellij/"* /root/.config/zellij/
    echo -e "${GREEN}[✓]${NC} Zellij config installed"
fi


# ───────────────────────────────────────────────────────────────────
# Install Eza (precompiled)
# ───────────────────────────────────────────────────────────────────

if [ ! -f "$BIN_DIR/eza" ]; then
    echo -e "${BLUE}[*]${NC} Installing Eza..."
    EZA_VERSION=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -sL "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-musl.tar.gz" | tar -xz -C "$BIN_DIR"
    chmod +x "$BIN_DIR/eza"
    echo -e "${GREEN}[✓]${NC} Eza installed"
fi

# ───────────────────────────────────────────────────────────────────
# Install Zoxide (precompiled)
# ───────────────────────────────────────────────────────────────────

if [ ! -f "$BIN_DIR/zoxide" ]; then
    echo -e "${BLUE}[*]${NC} Installing Zoxide..."
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh -s -- --bin-dir "$BIN_DIR"
    echo -e "${GREEN}[✓]${NC} Zoxide installed"
fi

# ───────────────────────────────────────────────────────────────────
# Install Bat (precompiled)
# ───────────────────────────────────────────────────────────────────

if [ ! -f "$BIN_DIR/bat" ] && ! command -v bat &> /dev/null; then
    echo -e "${BLUE}[*]${NC} Installing Bat..."
    BAT_VERSION=$(curl -s https://api.github.com/repos/sharkdp/bat/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -sL "https://github.com/sharkdp/bat/releases/latest/download/bat-v${BAT_VERSION}-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
    mv "/tmp/bat-v${BAT_VERSION}-x86_64-unknown-linux-musl/bat" "$BIN_DIR/bat"
    rm -rf "/tmp/bat-v${BAT_VERSION}-x86_64-unknown-linux-musl"
    chmod +x "$BIN_DIR/bat"
    echo -e "${GREEN}[✓]${NC} Bat installed"
fi

# ───────────────────────────────────────────────────────────────────
# Install Fd (precompiled)
# ───────────────────────────────────────────────────────────────────

if [ ! -f "$BIN_DIR/fd" ] && ! command -v fd &> /dev/null; then
    echo -e "${BLUE}[*]${NC} Installing Fd..."
    FD_VERSION=$(curl -s https://api.github.com/repos/sharkdp/fd/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -sL "https://github.com/sharkdp/fd/releases/latest/download/fd-v${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
    mv "/tmp/fd-v${FD_VERSION}-x86_64-unknown-linux-musl/fd" "$BIN_DIR/fd"
    rm -rf "/tmp/fd-v${FD_VERSION}-x86_64-unknown-linux-musl"
    chmod +x "$BIN_DIR/fd"
    echo -e "${GREEN}[✓]${NC} Fd installed"
fi

# ───────────────────────────────────────────────────────────────────
# Install Ripgrep (precompiled)
# ───────────────────────────────────────────────────────────────────

if [ ! -f "$BIN_DIR/rg" ] && ! command -v rg &> /dev/null; then
    echo -e "${BLUE}[*]${NC} Installing Ripgrep..."
    RG_VERSION=$(curl -s https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -sL "https://github.com/BurntSushi/ripgrep/releases/latest/download/ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
    mv "/tmp/ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl/rg" "$BIN_DIR/rg"
    rm -rf "/tmp/ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl"
    chmod +x "$BIN_DIR/rg"
    echo -e "${GREEN}[✓]${NC} Ripgrep installed"
fi

# ───────────────────────────────────────────────────────────────────
# Install Delta (precompiled)
# ───────────────────────────────────────────────────────────────────

if [ ! -f "$BIN_DIR/delta" ]; then
    echo -e "${BLUE}[*]${NC} Installing Git Delta..."
    DELTA_VERSION=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -sL "https://github.com/dandavison/delta/releases/latest/download/delta-${DELTA_VERSION}-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
    mv "/tmp/delta-${DELTA_VERSION}-x86_64-unknown-linux-musl/delta" "$BIN_DIR/delta"
    rm -rf "/tmp/delta-${DELTA_VERSION}-x86_64-unknown-linux-musl"
    chmod +x "$BIN_DIR/delta"

    # Configure git to use delta
    git config --global core.pager "delta" 2>/dev/null || true
    git config --global interactive.diffFilter "delta --color-only" 2>/dev/null || true
    git config --global delta.navigate true 2>/dev/null || true
    git config --global delta.side-by-side true 2>/dev/null || true
    git config --global delta.line-numbers true 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} Git Delta installed and configured"
fi

# ───────────────────────────────────────────────────────────────────
# Install Yazi (precompiled)
# ───────────────────────────────────────────────────────────────────

if [ ! -f "$BIN_DIR/yazi" ]; then
    echo -e "${BLUE}[*]${NC} Installing Yazi..."
    YAZI_VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -sL "https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip" -o /tmp/yazi.zip
    unzip -q /tmp/yazi.zip -d /tmp
    mv "/tmp/yazi-x86_64-unknown-linux-musl/yazi" "$BIN_DIR/yazi"
    rm -rf /tmp/yazi.zip "/tmp/yazi-x86_64-unknown-linux-musl"
    chmod +x "$BIN_DIR/yazi"
    echo -e "${GREEN}[✓]${NC} Yazi installed"
fi

if [ -d "$SETUP_DIR/yazi" ] && [ ! -d /root/.config/yazi ]; then
    mkdir -p /root/.config/yazi
    cp -r "$SETUP_DIR/yazi/"* /root/.config/yazi/
    echo -e "${GREEN}[✓]${NC} Yazi config installed"
fi

# Ensure all binaries are executable by everyone
if [ -d "$BIN_DIR" ]; then
    echo -e "${BLUE}[*]${NC} Fixing permissions on all binaries..."
    chmod 755 "$BIN_DIR"
    chmod +x "$BIN_DIR"/* 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} Permissions fixed"
fi

# ───────────────────────────────────────────────────────────────────
# Install Chaos client (precompiled)
# ───────────────────────────────────────────────────────────────────
# go install -v github.com/projectcdiscovery/chaos-client/cmd/chaos@latest
if [ ! -f "$BIN_DIR/chaos" ]; then
    echo -e "${BLUE}[*]${NC} Installing Chaos..."
    CHAOS_VERSION=$(curl -s https://api.github.com/repos/projectdiscovery/chaos-client/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -sL "https://github.com/projectdiscovery/chaos-client/releases/download/v${CHAOS_VERSION}/chaos-client_${CHAOS_VERSION}_linux_amd64.zip" -o /tmp/chaos.zip
    unzip -q /tmp/chaos.zip -d /tmp/chaos/
    mv "/tmp/chaos/chaos-client" "$BIN_DIR/chaos"
    rm -rf /tmp/chaos.zip "/tmp/chaos/"
    chmod +x "$BIN_DIR/chaos"
    echo -e "${GREEN}[✓]${NC} Chaos installed"
fi

# ───────────────────────────────────────────────────────────────────
# Install Notify (precompiled)
# ───────────────────────────────────────────────────────────────────
# go install -v github.com/projectdiscovery/notify/cmd/notify@latest
if [ ! -f "$BIN_DIR/notify" ]; then
    echo -e "${BLUE}[*]${NC} Installing Notify..."
    NOTIFY_VERSION=$(curl -s https://api.github.com/repos/projectdiscovery/notify/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -sL "https://github.com/projectdiscovery/notify/releases/download/v${NOTIFY_VERSION}/notify_${NOTIFY_VERSION}_linux_amd64.zip" -o /tmp/notify.zip
    unzip -q /tmp/notify.zip -d /tmp/notify
    mv "/tmp/notify/notify" "$BIN_DIR/notify"
    rm -rf /tmp/notify.zip "/tmp/notify"
    chmod +x "$BIN_DIR/notify"
    echo -e "${GREEN}[✓]${NC} Notify installed"
fi

if [ -d "$SETUP_DIR/notify" ] && [ ! -d /root/.config/notify ]; then
    mkdir -p /root/.config/notify/
    cp -r "$SETUP_DIR/notify/"* /root/.config/notify/
    echo -e "${GREEN}[✓]${NC} Notify config installed"
fi

# ───────────────────────────────────────────────────────────────────
# Configure subfinder
# ───────────────────────────────────────────────────────────────────
if [ -d "$SETUP_DIR/subfinder" ] && [ ! -d /root/.config/subfinder ]; then
    mkdir -p /root/.config/subfinder/
    cp -r "$SETUP_DIR/subfinder/"* /root/.config/subfinder/
    echo -e "${GREEN}[✓]${NC} Subfinder config installed"
fi

# ───────────────────────────────────────────────────────────────────
# Configure shodan-cli
# ───────────────────────────────────────────────────────────────────
if [ -d "$SETUP_DIR/shodan" ] && [ ! -d /root/.config/shodan ]; then
    mkdir -p /root/.config/shodan/
    cp -r "$SETUP_DIR/shodan/"* /root/.config/shodan/
    echo -e "${GREEN}[✓]${NC} Shodan config installed"
fi

# ───────────────────────────────────────────────────────────────────
# Update Project Discovery tools
# ───────────────────────────────────────────────────────────────────
# nuclei -update && nuclei -ut
# httpx -update
# subfinder -update
# asdf reshim

# ───────────────────────────────────────────────────────────────────
# Install Leviathan (precompiled)
# ───────────────────────────────────────────────────────────────────
# go install github.com/Ether-Security/leviathan@latest
if [ ! -f "$BIN_DIR/leviathan" ]; then
    echo -e "${BLUE}[*]${NC} Installing Leviathan..."
    NOTIFY_VERSION=$(curl -s https://api.github.com/repos/Ether-Security/leviathan/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -sL "https://github.com/Ether-Security/leviathan/releases/download/v${NOTIFY_VERSION}/leviathan_${NOTIFY_VERSION}_linux_amd64.tar.gz" | tar -xz -C "$BIN_DIR"
    chmod +x "$BIN_DIR/notify"
    echo -e "${GREEN}[✓]${NC} Leviathan installed"
fi

if [ -d "$SETUP_DIR/leviathan" ] && [ ! -d /root/.config/leviathan ]; then
    mkdir -p /root/.config/leviathan/
    cp -r "$SETUP_DIR/leviathan/"* /root/.config/leviathan/
    echo -e "${GREEN}[✓]${NC} Leviathan config installed"
fi

echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup Complete! Tools installed in $BIN_DIR${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
