#!/bin/bash

# Router to PC Tunnel Setup Script for Linux
# This script automates the setup of network tunneling on Linux systems

set -e

echo "============================================"
echo "Router to PC Tunnel Setup Script for Linux"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}This script should not be run as root. Use sudo when needed.${NC}"
   exit 1
fi

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    echo -e "${GREEN}Detected OS: $OS $VER${NC}"
}

# Function to install packages based on OS
install_packages() {
    echo -e "${YELLOW}Installing required packages...${NC}"
    
    case "$OS" in
        *Ubuntu*|*Debian*)
            sudo apt update
            sudo apt install -y iptables-persistent bridge-utils net-tools openssh-server
            ;;
        *CentOS*|*RHEL*)
            sudo yum install -y iptables-services bridge-utils net-tools openssh-server
            ;;
        *Fedora*)
            sudo dnf install -y iptables-services bridge-utils net-tools openssh-server
            ;;
        *)
            echo -e "${RED}Unsupported OS. Please install packages manually.${NC}"
            echo "Required packages: iptables-persistent bridge-utils net-tools openssh-server"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}Packages installed successfully!${NC}"
}

# Function to enable IP forwarding
enable_ip_forwarding() {
    echo -e "${YELLOW}Enabling IP forwarding...${NC}"
    
    # Enable for current session
    sudo sysctl -w net.ipv4.ip_forward=1
    sudo sysctl -w net.ipv6.conf.all.forwarding=1
    
    # Make it persistent
    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
    fi
    
    if ! grep -q "net.ipv6.conf.all.forwarding = 1" /etc/sysctl.conf; then
        echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
    fi
    
    echo -e "${GREEN}IP forwarding enabled!${NC}"
}

# Function to get network interface
get_network_interface() {
    echo -e "${YELLOW}Detecting network interfaces...${NC}"
    
    # Get default route interface
    DEFAULT_INTERFACE=$(ip route | grep default | head -1 | awk '{print $5}')
    
    if [ -z "$DEFAULT_INTERFACE" ]; then
        echo -e "${RED}Could not detect default network interface.${NC}"
        echo "Available interfaces:"
        ip link show
        read -p "Please enter your network interface name: " DEFAULT_INTERFACE
    fi
    
    echo -e "${GREEN}Using network interface: $DEFAULT_INTERFACE${NC}"
}

# Function to setup iptables rules
setup_iptables() {
    echo -e "${YELLOW}Setting up iptables rules...${NC}"
    
    # NAT rule for outgoing traffic
    sudo iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
    
    # Forward rules
    sudo iptables -A FORWARD -i $DEFAULT_INTERFACE -o $DEFAULT_INTERFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
    sudo iptables -A FORWARD -i $DEFAULT_INTERFACE -o $DEFAULT_INTERFACE -j ACCEPT
    
    # Save rules
    case "$OS" in
        *Ubuntu*|*Debian*)
            sudo netfilter-persistent save
            ;;
        *CentOS*|*RHEL*|*Fedora*)
            sudo service iptables save
            ;;
    esac
    
    echo -e "${GREEN}iptables rules configured!${NC}"
}

# Function to setup SSH
setup_ssh() {
    echo -e "${YELLOW}Setting up SSH server...${NC}"
    
    sudo systemctl enable ssh
    sudo systemctl start ssh
    
    echo -e "${GREEN}SSH server configured!${NC}"
}

# Function to create systemd service
create_service() {
    echo -e "${YELLOW}Creating systemd service...${NC}"
    
    # Create service file
    sudo tee /etc/systemd/system/router-tunnel.service > /dev/null <<EOF
[Unit]
Description=Router Tunnel Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-tunnel.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Create setup script
    sudo tee /usr/local/bin/setup-tunnel.sh > /dev/null <<EOF
#!/bin/bash
# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

# Setup iptables rules
iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
iptables -A FORWARD -i $DEFAULT_INTERFACE -o $DEFAULT_INTERFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i $DEFAULT_INTERFACE -o $DEFAULT_INTERFACE -j ACCEPT

echo "Tunnel setup completed"
EOF

    sudo chmod +x /usr/local/bin/setup-tunnel.sh
    
    # Enable service
    sudo systemctl daemon-reload
    sudo systemctl enable router-tunnel.service
    
    echo -e "${GREEN}Systemd service created and enabled!${NC}"
}

# Function to show status
show_status() {
    echo -e "${YELLOW}System Status:${NC}"
    echo "IP Forwarding IPv4: $(cat /proc/sys/net/ipv4/ip_forward)"
    echo "IP Forwarding IPv6: $(cat /proc/sys/net/ipv6/conf/all/forwarding)"
    echo "SSH Service: $(systemctl is-active ssh 2>/dev/null || echo 'inactive')"
    echo "Tunnel Service: $(systemctl is-active router-tunnel.service 2>/dev/null || echo 'inactive')"
    
    echo -e "\n${YELLOW}iptables NAT rules:${NC}"
    sudo iptables -t nat -L -n -v | grep -A 5 POSTROUTING || echo "No NAT rules found"
    
    echo -e "\n${YELLOW}Network interfaces:${NC}"
    ip addr show | grep -E "^[0-9]+:|inet "
}

# Main function
main() {
    echo -e "${GREEN}Starting router to PC tunnel setup...${NC}"
    
    detect_os
    install_packages
    get_network_interface
    enable_ip_forwarding
    setup_iptables
    setup_ssh
    create_service
    
    echo -e "\n${GREEN}Setup completed successfully!${NC}"
    echo -e "${YELLOW}To start the tunnel service manually, run:${NC}"
    echo "sudo systemctl start router-tunnel.service"
    
    echo -e "\n${YELLOW}To check service status:${NC}"
    echo "sudo systemctl status router-tunnel.service"
    
    show_status
    
    echo -e "\n${GREEN}Setup is complete! Your Linux system is now configured for network tunneling.${NC}"
}

# Check for help flag
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Router to PC Tunnel Setup Script for Linux"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --status       Show current system status"
    echo ""
    echo "This script will:"
    echo "  1. Install required packages"
    echo "  2. Enable IP forwarding"
    echo "  3. Configure iptables rules"
    echo "  4. Setup SSH server"
    echo "  5. Create systemd service for automatic startup"
    exit 0
fi

# Check for status flag
if [[ "$1" == "--status" ]]; then
    detect_os
    show_status
    exit 0
fi

# Run main function
main