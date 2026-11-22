#!/bin/bash

# Essential Software Installation Script
# Installs: MacTeX/TexLive, Conda environment with Python 3.12, and ures package

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install MacTeX on macOS
install_mactex() {
    log_info "Installing MacTeX on macOS..."

    if command_exists brew; then
        log_info "Using Homebrew to install MacTeX..."
        brew install --cask mactex
        log_success "MacTeX installed successfully via Homebrew"
    else
        log_warning "Homebrew not found. Please install MacTeX manually from:"
        log_warning "https://tug.org/mactex/mactex-download.html"
        return 1
    fi
}

# Install TexLive on Linux
install_texlive() {
    log_info "Installing TexLive on Linux..."

    # Detect Linux distribution
    if command_exists apt-get; then
        # Debian/Ubuntu
        log_info "Detected Debian/Ubuntu system"
        sudo apt-get update
        sudo apt-get install -y texlive-full
        log_success "TexLive installed successfully via apt"
    elif command_exists yum; then
        # RHEL/CentOS/Fedora (older versions)
        log_info "Detected RHEL/CentOS system"
        sudo yum install -y texlive-scheme-full
        log_success "TexLive installed successfully via yum"
    elif command_exists dnf; then
        # Fedora (newer versions)
        log_info "Detected Fedora system"
        sudo dnf install -y texlive-scheme-full
        log_success "TexLive installed successfully via dnf"
    elif command_exists pacman; then
        # Arch Linux
        log_info "Detected Arch Linux system"
        sudo pacman -S --noconfirm texlive-most
        log_success "TexLive installed successfully via pacman"
    else
        log_error "Unsupported Linux distribution. Please install TexLive manually."
        return 1
    fi
}

# Install LaTeX based on OS
install_latex() {
    local os=$(detect_os)

    log_info "Installing LaTeX distribution for $os..."

    case $os in
        "macos")
            # Check if MacTeX is already installed
            if command_exists pdflatex && [[ -d "/usr/local/texlive" ]]; then
                log_success "MacTeX is already installed"
            else
                install_mactex
            fi
            ;;
        "linux")
            # Check if TexLive is already installed
            if command_exists pdflatex; then
                log_success "TexLive is already installed"
            else
                install_texlive
            fi
            ;;
        *)
            log_error "Unsupported operating system: $OSTYPE"
            return 1
            ;;
    esac
}

# Check and setup Conda
setup_conda() {
    log_info "Checking for Conda installation..."

    if command_exists conda; then
        log_success "Conda is already installed"

        # Initialize conda for bash if not already done
        if ! grep -q "conda initialize" ~/.bashrc 2>/dev/null; then
            log_info "Initializing Conda for bash..."
            conda init bash
            log_info "Please restart your terminal or run 'source ~/.bashrc' after this script completes"
        fi

        return 0
    else
        log_warning "Conda is not installed on your system"
        log_warning "Please install Conda (Miniconda or Anaconda) from:"
        log_warning "https://docs.conda.io/en/latest/miniconda.html"
        log_warning "or"
        log_warning "https://www.anaconda.com/products/distribution"
        return 1
    fi
}

# Create conda environment and install ures
setup_python_environment() {
    local env_name="LaTeX-Env"

    log_info "Setting up Python environment with conda..."

    # Check if environment already exists
    if conda env list | grep -q "^${env_name} "; then
        log_warning "Environment '${env_name}' already exists"
        read -p "Do you want to remove and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing environment..."
            conda env remove -n "$env_name" -y
        else
            log_info "Using existing environment..."
            conda activate "$env_name"
            # Check if ures is already installed
            if conda list -n "$env_name" | grep -q "ures"; then
                log_success "ures is already installed in environment '$env_name'"
                return 0
            fi
        fi
    fi

    if ! conda env list | grep -q "^${env_name} "; then
        log_info "Creating conda environment '$env_name' with Python 3.12..."
        conda create -n "$env_name" python=3.12 -y
    fi

    log_info "Activating environment '$env_name'..."
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate "$env_name"

    log_info "Installing ures package..."
    pip install ures==3.2.1

    log_success "Python environment '$env_name' created successfully with ures installed"
    log_info "To activate this environment, run: conda activate $env_name"
}

# Main execution
main() {
    log_info "Starting essential software installation..."
    log_info "Detected OS: $(detect_os)"
    echo

    # Install LaTeX
    log_info "=== Installing LaTeX Distribution ==="
    if install_latex; then
        log_success "LaTeX installation completed"
    else
        log_error "LaTeX installation failed"
        exit 1
    fi
    echo

    # Setup Conda
    log_info "=== Setting up Conda Environment ==="
    if setup_conda; then
        # If conda is available, setup Python environment
        if setup_python_environment; then
            log_success "Python environment setup completed"
        else
            log_error "Python environment setup failed"
            exit 1
        fi
    else
        log_error "Cannot proceed without Conda. Please install Conda first."
        exit 1
    fi
    echo

    log_success "All installations completed successfully!"
    log_info "Summary of what was installed:"
    echo "  • LaTeX distribution (MacTeX/TexLive)"
    echo "  • Conda environment 'LaTeX-Env' with Python 3.12"
    echo "  • ures package in the conda environment"
    echo
    log_info "To use the Python environment: conda activate LaTeX-Env"
}

# Run main function
main "$@"
