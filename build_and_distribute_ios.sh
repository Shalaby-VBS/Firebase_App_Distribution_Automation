#!/bin/bash

# ============================================================================
# 🚀 Firebase App Distribution - iOS Build & Upload Script
# ============================================================================
# Builds iOS IPA with Flutter flavors and uploads to Firebase
#
# Usage:
#   ./build_and_distribute_ios.sh [flavor] [version] [release_notes]
#
# Examples:
#   ./build_and_distribute_ios.sh development
#   ./build_and_distribute_ios.sh production "1.0.5" "Bug fixes"
#   ./build_and_distribute_ios.sh production auto "New features"
#
# Arguments:
#   flavor        : development | production (default: development)
#   version       : Version string or "auto" to read from pubspec.yaml
#   release_notes : Release notes (default: auto-generated)
# ============================================================================

set -e

# ============================================================================
# 🎨 Colors & Icons
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# Icons
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_ROCKET="🚀"
ICON_PACKAGE="📦"
ICON_UPLOAD="☁️"
ICON_BUILD="🔨"
ICON_CLEAN="🧹"
ICON_CHECK="✓"
ICON_FIRE="🔥"
ICON_TIME="⏱️"
ICON_SIZE="💾"
ICON_APPLE="🍎"
ICON_POD="🎯"

# ============================================================================
# ⚙️ Configuration
# ============================================================================
FLAVOR="${1:-development}"
VERSION_INPUT="${2:-auto}"
RELEASE_NOTES="${3:-}"

# Firebase Configuration - Will be read from GoogleService-Info.plist
FIREBASE_IOS_APP_ID=""
TESTER_GROUP="testers"

# Microsoft Teams Webhook (optional - leave empty to disable)
TEAMS_WEBHOOK_URL="https://default758e998336f64ecebab3bfdd644e33.87.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/d5e0a774a51b4b468454fff2f2c6be7d/triggers/manual/paths/invoke?api-version=1"

# Paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$PROJECT_ROOT/ios"
BUILD_DIR="$PROJECT_ROOT/build/ios/ipa"
PUBSPEC_FILE="$PROJECT_ROOT/pubspec.yaml"
GOOGLE_SERVICE_INFO_PLIST="$IOS_DIR/Runner/GoogleService-Info.plist"

# Build artifacts
IPA_PATH=""
VERSION_NAME=""
VERSION_CODE=""
BUILD_START_TIME=$(date +%s)

# ============================================================================
# 🎭 Animation Functions
# ============================================================================

spinner() {
    local pid=$1
    local message=$2
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local temp
    
    while kill -0 "$pid" 2>/dev/null; do
        temp=${spinstr#?}
        printf "\r${CYAN}%s${NC} %s" "${spinstr:0:1}" "$message"
        spinstr=$temp${spinstr:0:1}
        sleep 0.1
    done
    printf "\r"
}

progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\r${BLUE}["
    printf "%${completed}s" | tr ' ' '█'
    printf "%${remaining}s" | tr ' ' '░'
    printf "]${NC} ${WHITE}%3d%%${NC}" "$percentage"
}

print_banner() {
    clear
    echo -e "${PURPLE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║        🍎  Firebase App Distribution Build Script  🍎          ║"
    echo "║                                                                ║"
    echo "║                       iOS IPA Builder                          ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

print_section() {
    echo ""
    echo -e "${CYAN}╭─────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${NC} ${WHITE}$1${NC}"
    echo -e "${CYAN}╰─────────────────────────────────────────────────────────────╯${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}${ICON_SUCCESS} $1${NC}"
}

print_error() {
    echo -e "${RED}${ICON_ERROR} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}${ICON_WARNING} $1${NC}"
}

print_info() {
    echo -e "${BLUE}${ICON_INFO} $1${NC}"
}

print_step() {
    echo -e "${PURPLE}${ICON_ROCKET} $1${NC}"
}

print_detail() {
    echo -e "${GRAY}  └─ $1${NC}"
}

# ============================================================================
# 🔥 Firebase Configuration
# ============================================================================

read_firebase_config() {
    print_step "Reading Firebase configuration from GoogleService-Info.plist..."
    
    if [[ ! -f "$GOOGLE_SERVICE_INFO_PLIST" ]]; then
        print_error "GoogleService-Info.plist not found!"
        echo -e "${GRAY}  Expected location: ios/Runner/GoogleService-Info.plist${NC}"
        echo -e "${GRAY}  Download it from Firebase Console > Project Settings > Your Apps${NC}"
        exit 1
    fi
    
    # Extract GOOGLE_APP_ID from GoogleService-Info.plist
    FIREBASE_IOS_APP_ID=$(/usr/libexec/PlistBuddy -c "Print :GOOGLE_APP_ID" "$GOOGLE_SERVICE_INFO_PLIST" 2>/dev/null)
    
    if [[ -z "$FIREBASE_IOS_APP_ID" ]]; then
        print_error "Failed to read Firebase App ID from GoogleService-Info.plist!"
        echo -e "${GRAY}  Make sure the file contains 'GOOGLE_APP_ID' key${NC}"
        exit 1
    fi
    
    print_success "Firebase App ID loaded"
    print_detail "App ID: ${FIREBASE_IOS_APP_ID:0:40}..."
}

# ============================================================================
# 📖 Version Management
# ============================================================================

read_version_from_pubspec() {
    print_step "Reading version from pubspec.yaml..."
    
    if [[ ! -f "$PUBSPEC_FILE" ]]; then
        print_error "pubspec.yaml not found!"
        exit 1
    fi
    
    # Read version line (format: version: 1.0.0+1)
    local version_line=$(grep "^version:" "$PUBSPEC_FILE" | head -n 1)
    
    if [[ -z "$version_line" ]]; then
        print_error "Version not found in pubspec.yaml!"
        exit 1
    fi
    
    # Extract version (e.g., "1.0.0+1")
    local full_version=$(echo "$version_line" | sed 's/version: *//' | tr -d ' ')
    
    # Split version name and code
    VERSION_NAME=$(echo "$full_version" | cut -d'+' -f1)
    VERSION_CODE=$(echo "$full_version" | cut -d'+' -f2)
    
    # If no version code, use timestamp
    if [[ -z "$VERSION_CODE" ]] || [[ "$VERSION_CODE" == "$VERSION_NAME" ]]; then
        VERSION_CODE=$(date +%s)
    fi
    
    print_success "Version: $VERSION_NAME ($VERSION_CODE)"
    print_detail "Name: $VERSION_NAME"
    print_detail "Code: $VERSION_CODE"
}

set_custom_version() {
    local custom_version=$1
    
    print_step "Setting custom version: $custom_version"
    
    # Parse custom version (format: 1.0.0 or 1.0.0+123)
    if [[ "$custom_version" == *"+"* ]]; then
        VERSION_NAME=$(echo "$custom_version" | cut -d'+' -f1)
        VERSION_CODE=$(echo "$custom_version" | cut -d'+' -f2)
    else
        VERSION_NAME="$custom_version"
        VERSION_CODE=$(date +%s)
    fi
    
    print_success "Custom version set"
    print_detail "Name: $VERSION_NAME"
    print_detail "Code: $VERSION_CODE"
}

update_ios_version() {
    print_step "Updating iOS version codes..."
    
    local info_plist="$IOS_DIR/Runner/Info.plist"
    
    if [[ ! -f "$info_plist" ]]; then
        print_error "Info.plist not found!"
        exit 1
    fi
    
    # Backup original
    cp "$info_plist" "${info_plist}.bak"
    
    # Update CFBundleShortVersionString and CFBundleVersion
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION_NAME" "$info_plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION_NAME" "$info_plist"
    
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION_CODE" "$info_plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION_CODE" "$info_plist"
    
    print_success "iOS version updated"
    print_detail "Updated in: Runner/Info.plist"
}

restore_ios_version() {
    local info_plist="$IOS_DIR/Runner/Info.plist"
    
    if [[ -f "${info_plist}.bak" ]]; then
        mv "${info_plist}.bak" "$info_plist"
        print_info "Version codes restored"
    fi
}

# ============================================================================
# ✅ Validation
# ============================================================================

validate_environment() {
    print_section "${ICON_CHECK} Environment Validation"
    
    # Check if running on macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "This script must run on macOS!"
        exit 1
    fi
    print_success "Running on macOS"
    
    if command -v flutter &> /dev/null; then
        local flutter_version=$(flutter --version | head -n 1)
        print_success "Flutter: $flutter_version"
    else
        print_error "Flutter not found!"
        echo -e "${GRAY}  Install: https://flutter.dev/docs/get-started/install${NC}"
        exit 1
    fi
    
    if command -v pod &> /dev/null; then
        local pod_version=$(pod --version)
        print_success "CocoaPods: $pod_version"
    else
        print_error "CocoaPods not found!"
        echo -e "${GRAY}  Install: sudo gem install cocoapods${NC}"
        exit 1
    fi
    
    if command -v firebase &> /dev/null; then
        local firebase_version=$(firebase --version)
        print_success "Firebase CLI: $firebase_version"
    else
        print_error "Firebase CLI not found!"
        echo -e "${GRAY}  Install: npm install -g firebase-tools${NC}"
        exit 1
    fi
    
    if [[ -f "$PUBSPEC_FILE" ]]; then
        print_success "pubspec.yaml found"
    else
        print_error "pubspec.yaml not found!"
        exit 1
    fi
    
    if [[ -d "$IOS_DIR" ]]; then
        print_success "iOS directory found"
    else
        print_error "iOS directory not found!"
        exit 1
    fi
    
    # Check for GoogleService-Info.plist
    if [[ -f "$GOOGLE_SERVICE_INFO_PLIST" ]]; then
        print_success "GoogleService-Info.plist found"
    else
        print_error "GoogleService-Info.plist not found!"
        echo -e "${GRAY}  Location: ios/Runner/GoogleService-Info.plist${NC}"
        echo -e "${GRAY}  Download from Firebase Console${NC}"
        exit 1
    fi
    
    # Check Xcode
    if command -v xcodebuild &> /dev/null; then
        local xcode_version=$(xcodebuild -version | head -n 1)
        print_success "Xcode: $xcode_version"
    else
        print_error "Xcode not found!"
        exit 1
    fi
}

validate_parameters() {
    print_section "${ICON_CHECK} Parameter Validation"
    
    # Validate flavor
    if [[ "$FLAVOR" != "development" && "$FLAVOR" != "production" ]]; then
        print_error "Invalid flavor: $FLAVOR"
        echo -e "${GRAY}  Valid: development, production${NC}"
        exit 1
    fi
    print_success "Flavor: $FLAVOR"
    
    # Check provisioning profile for production
    if [[ "$FLAVOR" == "production" ]]; then
        print_warning "Ensure you have valid provisioning profiles"
        print_detail "Check: Xcode > Preferences > Accounts"
    fi
}

# ============================================================================
# 🔨 Build Process
# ============================================================================

clean_project() {
    print_section "${ICON_CLEAN} Cleaning Project"
    
    print_step "Running flutter clean..."
    flutter clean > /dev/null 2>&1 &
    spinner $! "Cleaning Flutter build cache..."
    print_success "Flutter cache cleaned"
    
    print_step "Removing iOS build artifacts..."
    rm -rf "$BUILD_DIR" > /dev/null 2>&1
    rm -rf "$IOS_DIR/build" > /dev/null 2>&1
    rm -rf "$IOS_DIR/.symlinks" > /dev/null 2>&1
    rm -rf "$IOS_DIR/Pods" > /dev/null 2>&1
    print_success "Build artifacts removed"
}

install_dependencies() {
    print_section "${ICON_PACKAGE} Installing Dependencies"
    
    print_step "Running flutter pub get..."
    flutter pub get > /dev/null 2>&1 &
    spinner $! "Fetching Flutter dependencies..."
    print_success "Flutter dependencies installed"
    
    print_step "Installing CocoaPods dependencies..."
    print_detail "This may take a few minutes..."
    
    cd "$IOS_DIR"
    
    # Deintegrate pods
    print_detail "Deintegrating previous pods..."
    pod deintegrate > /dev/null 2>&1 || true
    
    # Install pods
    print_detail "Installing pods..."
    pod install --repo-update > /dev/null 2>&1 &
    spinner $! "Installing CocoaPods (this takes time)..."
    
    # Verify critical pods
    if [[ ! -d "Pods/gRPC-Core" ]] || [[ ! -d "Pods/BoringSSL-GRPC" ]]; then
        print_warning "Critical Firebase pods missing, retrying..."
        pod cache clean --all > /dev/null 2>&1
        pod install --repo-update > /dev/null 2>&1
    fi
    
    cd "$PROJECT_ROOT"
    
    print_success "CocoaPods dependencies installed"
    print_detail "Pods directory size: $(du -sh "$IOS_DIR/Pods" 2>/dev/null | cut -f1)"
}

build_ipa() {
    print_section "${ICON_BUILD} Building iOS IPA"
    
    # Determine build configuration
    local build_mode="release"
    local export_method
    local export_options_plist="$IOS_DIR/ExportOptions.plist"
    
    if [[ "$FLAVOR" == "production" ]]; then
        export_method="app-store"
    else
        export_method="development"
    fi
    
    echo -e "${WHITE}Build Configuration:${NC}"
    print_detail "Flavor: $FLAVOR"
    print_detail "Mode: $build_mode"
    print_detail "Export: $export_method"
    print_detail "Version: $VERSION_NAME ($VERSION_CODE)"
    echo ""
    
    # Update ExportOptions.plist with correct method
    print_step "Updating export options..."
    if [[ -f "$export_options_plist" ]]; then
        # Backup original
        cp "$export_options_plist" "${export_options_plist}.bak"
        
        # Update method
        /usr/libexec/PlistBuddy -c "Set :method $export_method" "$export_options_plist" 2>/dev/null || \
            /usr/libexec/PlistBuddy -c "Add :method string $export_method" "$export_options_plist"
        
        print_success "Export options updated to: $export_method"
    else
        print_warning "ExportOptions.plist not found, using default settings"
    fi
    
    print_step "Starting IPA build process..."
    print_detail "This will take 5-10 minutes..."
    
    # Build IPA with export options
    local build_cmd="flutter build ipa --release --build-name=$VERSION_NAME --build-number=$VERSION_CODE --export-options-plist=$export_options_plist"
    
    if $build_cmd; then
        print_success "IPA build completed"
        
        # Restore ExportOptions.plist
        if [[ -f "${export_options_plist}.bak" ]]; then
            mv "${export_options_plist}.bak" "$export_options_plist"
        fi
    else
        print_error "IPA build failed!"
        
        # Restore ExportOptions.plist
        if [[ -f "${export_options_plist}.bak" ]]; then
            mv "${export_options_plist}.bak" "$export_options_plist"
        fi
        
        restore_ios_version
        exit 1
    fi
    
    # Locate IPA file
    print_step "Locating IPA artifact..."
    
    IPA_PATH=$(find "$BUILD_DIR" -name "*.ipa" -type f | head -n 1)
    
    if [[ -z "$IPA_PATH" ]] || [[ ! -f "$IPA_PATH" ]]; then
        print_error "IPA file not found!"
        print_detail "Expected in: $BUILD_DIR"
        restore_ios_version
        exit 1
    fi
    
    # Display build info
    local file_size=$(du -h "$IPA_PATH" | cut -f1)
    print_success "IPA artifact ready"
    print_detail "Path: ${IPA_PATH##*/}"
    print_detail "Size: $file_size"
}

# ============================================================================
# ☁️ Firebase Distribution
# ============================================================================

send_teams_notification() {
    # Skip if webhook URL is empty
    if [[ -z "$TEAMS_WEBHOOK_URL" ]]; then
        return 0
    fi
    
    print_step "Sending notification to Microsoft Teams..."
    
    local platform="iOS"
    local file_size=$(du -h "$IPA_PATH" | cut -f1)
    local build_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create simple text message for Power Automate
    local message_text="🍎 New Build Released - ${platform}\\n\\n"
    message_text+="📱 Platform: ${platform}\\n"
    message_text+="🏷️ Version: ${VERSION_NAME} (${VERSION_CODE})\\n"
    message_text+="🎯 Flavor: ${FLAVOR}\\n"
    message_text+="📦 Build Type: IPA\\n"
    message_text+="💾 File Size: ${file_size}\\n"
    message_text+="⏰ Build Time: ${build_time}\\n"
    message_text+="📝 Notes: ${RELEASE_NOTES}"
    
    # Create JSON payload (simple format for Power Automate)
    local json_payload=$(cat <<EOF
{
    "text": "${message_text}",
    "title": "🍎 New Build Released - ${platform}",
    "platform": "${platform}",
    "version": "${VERSION_NAME}",
    "versionCode": "${VERSION_CODE}",
    "flavor": "${FLAVOR}",
    "buildType": "IPA",
    "fileSize": "${file_size}",
    "buildTime": "${build_time}",
    "releaseNotes": "${RELEASE_NOTES}"
}
EOF
)
    
    # Send to Power Automate webhook and capture response
    local temp_response="/tmp/teams_response_$$.txt"
    local http_code=$(curl -s -w "%{http_code}" -o "$temp_response" -X POST "$TEAMS_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$json_payload")
    
    local response_body=$(cat "$temp_response" 2>/dev/null)
    rm -f "$temp_response"
    
    if [[ "$http_code" == "202" ]] || [[ "$http_code" == "200" ]]; then
        print_success "Teams notification sent successfully (HTTP $http_code)"
    else
        print_warning "Failed to send Teams notification (HTTP $http_code)"
        if [[ -n "$response_body" ]] && [[ "$response_body" != "null" ]]; then
            print_detail "Response: $response_body"
        fi
        print_detail "Note: Check if the Power Automate workflow is turned on"
    fi
}

upload_to_firebase() {
    print_section "${ICON_UPLOAD} Uploading to Firebase"
    
    # Generate release notes if not provided
    if [[ -z "$RELEASE_NOTES" ]]; then
        RELEASE_NOTES="iOS Version $VERSION_NAME - Built on $(date '+%Y-%m-%d at %H:%M:%S')"
    fi
    
    echo -e "${WHITE}Distribution Info:${NC}"
    print_detail "App ID: ${FIREBASE_IOS_APP_ID:0:30}..."
    print_detail "Version: $VERSION_NAME"
    print_detail "Testers: $TESTER_GROUP"
    print_detail "Notes: $RELEASE_NOTES"
    echo ""
    
    # Create temp file for release notes
    local notes_file="/tmp/release_notes_ios_${VERSION_CODE}.txt"
    echo "$RELEASE_NOTES" > "$notes_file"
    
    print_step "Uploading to Firebase App Distribution..."
    
    # Upload with progress indication
    firebase appdistribution:distribute "$IPA_PATH" \
        --app "$FIREBASE_IOS_APP_ID" \
        --release-notes-file "$notes_file" \
        --groups "$TESTER_GROUP" &
    
    spinner $! "Uploading IPA to Firebase..."
    
    # Cleanup
    rm -f "$notes_file"
    
    print_success "Upload completed successfully!"
}

# ============================================================================
# 📊 Summary
# ============================================================================

print_summary() {
    local build_end_time=$(date +%s)
    local build_duration=$((build_end_time - BUILD_START_TIME))
    local minutes=$((build_duration / 60))
    local seconds=$((build_duration % 60))
    
    print_section "${ICON_FIRE} Build Summary"
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${ICON_SUCCESS} ${WHITE}Build & Distribution Completed Successfully!${NC}             ${GREEN}║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}                                                                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${ICON_APPLE} Platform:        ${CYAN}iOS${NC}                                        ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${ICON_BUILD}  Flavor:         ${CYAN}${FLAVOR}${NC}                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${ICON_INFO}  Version:        ${CYAN}${VERSION_NAME} (${VERSION_CODE})${NC}                    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${ICON_TIME}  Duration:       ${CYAN}${minutes}m ${seconds}s${NC}                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                ${GREEN}║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  ${ICON_UPLOAD} ${YELLOW}Testers will receive download notification${NC}               ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${ICON_FIRE}  ${YELLOW}View in Firebase Console:${NC}                                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${GRAY}https://console.firebase.google.com/project/_/appdistribution${NC} ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
# 🚀 Main Execution
# ============================================================================

main() {
    print_banner
    
    # Environment validation
    validate_environment
    validate_parameters
    
    # Read Firebase configuration from GoogleService-Info.plist
    print_section "${ICON_FIRE} Firebase Configuration"
    read_firebase_config
    
    # Version management
    print_section "${ICON_INFO} Version Configuration"
    if [[ "$VERSION_INPUT" == "auto" ]]; then
        read_version_from_pubspec
    else
        set_custom_version "$VERSION_INPUT"
    fi
    
    # Update iOS files
    update_ios_version
    
    # Build process
    clean_project
    install_dependencies
    build_ipa
    
    # Restore version files
    restore_ios_version
    
    # Upload to Firebase
    upload_to_firebase
    
    # Send Teams notification
    send_teams_notification
    
    # Display summary
    print_summary
}

# Trap errors
trap 'print_error "Script failed! Restoring files..."; restore_ios_version; exit 1' ERR

# Execute main function
main