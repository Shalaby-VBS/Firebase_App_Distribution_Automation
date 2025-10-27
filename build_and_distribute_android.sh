#!/bin/bash

# ============================================================================
# 🚀 Firebase App Distribution - Android Build & Upload Script
# ============================================================================
# Builds Android APK/AAB with Flutter flavors and uploads to Firebase
#
# Usage:
#   ./build_and_distribute_android.sh [flavor] [build_type] [version] [release_notes]
#
# Examples:
#   ./build_and_distribute_android.sh development apk
#   ./build_and_distribute_android.sh production aab "1.0.5" "Bug fixes"
#   ./build_and_distribute_android.sh production apk auto "New features"
#
# Arguments:
#   flavor        : development | production (default: development)
#   build_type    : apk | aab (default: apk)
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

# ============================================================================
# ⚙️ Configuration
# ============================================================================
FLAVOR="${1:-development}"
BUILD_TYPE="${2:-apk}"
VERSION_INPUT="${3:-auto}"
RELEASE_NOTES="${4:-}"

# Firebase Configuration - Will be read from google-services.json
FIREBASE_ANDROID_APP_ID=""
TESTER_GROUP="testers"

# Microsoft Teams Webhook (optional - leave empty to disable)
TEAMS_WEBHOOK_URL="https://default758e998336f64ecebab3bfdd644e33.87.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/d5e0a774a51b4b468454fff2f2c6be7d/triggers/manual/paths/invoke?api-version=1"

# Paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$PROJECT_ROOT/android"
PUBSPEC_FILE="$PROJECT_ROOT/pubspec.yaml"
GOOGLE_SERVICES_FILE="$ANDROID_DIR/app/google-services.json"

# Build artifacts
BUILD_OUTPUT=""
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
    echo "║        🚀  Firebase App Distribution Build Script  🚀          ║"
    echo "║                                                                ║"
    echo "║                     Android APK/AAB Builder                    ║"
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
    print_step "Reading Firebase configuration from google-services.json..."
    
    if [[ ! -f "$GOOGLE_SERVICES_FILE" ]]; then
        print_error "google-services.json not found!"
        echo -e "${GRAY}  Expected location: android/app/google-services.json${NC}"
        echo -e "${GRAY}  Download it from Firebase Console > Project Settings > Your Apps${NC}"
        exit 1
    fi
    
    # Extract mobilesdk_app_id from google-services.json
    # This works for both single and multi-flavor configurations
    FIREBASE_ANDROID_APP_ID=$(grep -m 1 '"mobilesdk_app_id"' "$GOOGLE_SERVICES_FILE" | sed 's/.*"mobilesdk_app_id": *"\([^"]*\)".*/\1/')
    
    if [[ -z "$FIREBASE_ANDROID_APP_ID" ]]; then
        print_error "Failed to read Firebase App ID from google-services.json!"
        echo -e "${GRAY}  Make sure the file contains 'mobilesdk_app_id' field${NC}"
        exit 1
    fi
    
    print_success "Firebase App ID loaded"
    print_detail "App ID: ${FIREBASE_ANDROID_APP_ID:0:40}..."
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

update_android_version() {
    print_step "Updating Android version codes..."
    
    local gradle_file="$ANDROID_DIR/app/build.gradle"
    
    if [[ ! -f "$gradle_file" ]]; then
        print_error "build.gradle not found!"
        exit 1
    fi
    
    # Backup original
    cp "$gradle_file" "${gradle_file}.bak"
    
    # Update versionCode and versionName
    sed -i.tmp "s/versionCode [0-9]*/versionCode $VERSION_CODE/" "$gradle_file"
    sed -i.tmp "s/versionName \"[^\"]*\"/versionName \"$VERSION_NAME\"/" "$gradle_file"
    rm -f "${gradle_file}.tmp"
    
    print_success "Android version updated"
    print_detail "Updated in: app/build.gradle"
}

restore_android_version() {
    local gradle_file="$ANDROID_DIR/app/build.gradle"
    
    if [[ -f "${gradle_file}.bak" ]]; then
        mv "${gradle_file}.bak" "$gradle_file"
        print_info "Version codes restored"
    fi
}

# ============================================================================
# ✅ Validation
# ============================================================================

validate_environment() {
    print_section "${ICON_CHECK} Environment Validation"
    
    if command -v flutter &> /dev/null; then
        local flutter_version=$(flutter --version | head -n 1)
        print_success "Flutter: $flutter_version"
    else
        print_error "Flutter not found!"
        echo -e "${GRAY}  Install: https://flutter.dev/docs/get-started/install${NC}"
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
    
    if [[ -d "$ANDROID_DIR" ]]; then
        print_success "Android directory found"
    else
        print_error "Android directory not found!"
        exit 1
    fi
    
    # Check for google-services.json
    if [[ -f "$GOOGLE_SERVICES_FILE" ]]; then
        print_success "google-services.json found"
    else
        print_error "google-services.json not found!"
        echo -e "${GRAY}  Location: android/app/google-services.json${NC}"
        echo -e "${GRAY}  Download from Firebase Console${NC}"
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
    
    # Validate build type
    if [[ "$BUILD_TYPE" != "apk" && "$BUILD_TYPE" != "aab" ]]; then
        print_error "Invalid build type: $BUILD_TYPE"
        echo -e "${GRAY}  Valid: apk, aab${NC}"
        exit 1
    fi
    local build_type_upper=$(echo "$BUILD_TYPE" | tr '[:lower:]' '[:upper:]')
    print_success "Build type: $build_type_upper"
    
    # Check keystore for production
    if [[ "$FLAVOR" == "production" ]]; then
        if [[ ! -f "$ANDROID_DIR/key.properties" ]]; then
            print_warning "key.properties not found"
            print_detail "Production build may fail without signing"
        else
            print_success "Keystore configured"
        fi
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
    
    print_step "Removing Android build artifacts..."
    rm -rf "$ANDROID_DIR/app/build" > /dev/null 2>&1
    rm -rf "$ANDROID_DIR/.gradle" > /dev/null 2>&1
    rm -rf "$PROJECT_ROOT/build" > /dev/null 2>&1
    print_success "Build artifacts removed"
}

install_dependencies() {
    print_section "${ICON_PACKAGE} Installing Dependencies"
    
    print_step "Running flutter pub get..."
    flutter pub get > /dev/null 2>&1 &
    spinner $! "Fetching dependencies..."
    print_success "Dependencies installed"
}

build_android() {
    local build_type_upper=$(echo "$BUILD_TYPE" | tr '[:lower:]' '[:upper:]')
    print_section "${ICON_BUILD} Building Android $build_type_upper"
    
    echo -e "${WHITE}Build Configuration:${NC}"
    print_detail "Flavor: $FLAVOR"
    print_detail "Type: $build_type_upper"
    print_detail "Version: $VERSION_NAME ($VERSION_CODE)"
    echo ""
    
    print_step "Starting build process..."
    
    local build_cmd
    if [[ "$BUILD_TYPE" == "apk" ]]; then
        build_cmd="flutter build apk --release --flavor $FLAVOR --build-name=$VERSION_NAME --build-number=$VERSION_CODE"
    else
        build_cmd="flutter build appbundle --release --flavor $FLAVOR --build-name=$VERSION_NAME --build-number=$VERSION_CODE"
    fi
    
    # Execute build
    if $build_cmd; then
        print_success "Build completed successfully"
    else
        print_error "Build failed!"
        restore_android_version
        exit 1
    fi
    
    # Locate build output
    print_step "Locating build artifacts..."
    
    if [[ "$BUILD_TYPE" == "apk" ]]; then
        BUILD_OUTPUT=$(find "$PROJECT_ROOT/build/app/outputs/flutter-apk" -name "app-${FLAVOR}-release.apk" | head -n 1)
    else
        BUILD_OUTPUT=$(find "$PROJECT_ROOT/build/app/outputs/bundle" -name "app-${FLAVOR}-release.aab" | head -n 1)
    fi
    
    if [[ -z "$BUILD_OUTPUT" ]] || [[ ! -f "$BUILD_OUTPUT" ]]; then
        print_error "Build output not found!"
        restore_android_version
        exit 1
    fi
    
    # Display build info
    local file_size=$(du -h "$BUILD_OUTPUT" | cut -f1)
    print_success "Build artifact ready"
    print_detail "Path: ${BUILD_OUTPUT##*/}"
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
    
    local build_type_upper=$(echo "$BUILD_TYPE" | tr '[:lower:]' '[:upper:]')
    local platform="Android"
    local file_size=$(du -h "$BUILD_OUTPUT" | cut -f1)
    local build_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create simple text message for Power Automate
    local message_text="🚀 New Build Released - ${platform}\\n\\n"
    message_text+="📱 Platform: ${platform}\\n"
    message_text+="🏷️ Version: ${VERSION_NAME} (${VERSION_CODE})\\n"
    message_text+="🎯 Flavor: ${FLAVOR}\\n"
    message_text+="📦 Build Type: ${build_type_upper}\\n"
    message_text+="💾 File Size: ${file_size}\\n"
    message_text+="⏰ Build Time: ${build_time}\\n"
    message_text+="📝 Notes: ${RELEASE_NOTES}"
    
    # Create JSON payload (simple format for Power Automate)
    local json_payload=$(cat <<EOF
{
    "text": "${message_text}",
    "title": "🚀 New Build Released - ${platform}",
    "platform": "${platform}",
    "version": "${VERSION_NAME}",
    "versionCode": "${VERSION_CODE}",
    "flavor": "${FLAVOR}",
    "buildType": "${build_type_upper}",
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
        RELEASE_NOTES="Version $VERSION_NAME - Built on $(date '+%Y-%m-%d at %H:%M:%S')"
    fi
    
    echo -e "${WHITE}Distribution Info:${NC}"
    print_detail "App ID: ${FIREBASE_ANDROID_APP_ID:0:30}..."
    print_detail "Version: $VERSION_NAME"
    print_detail "Testers: $TESTER_GROUP"
    print_detail "Notes: $RELEASE_NOTES"
    echo ""
    
    # Create temp file for release notes
    local notes_file="/tmp/release_notes_${BUILD_TYPE}_${VERSION_CODE}.txt"
    echo "$RELEASE_NOTES" > "$notes_file"
    
    print_step "Uploading to Firebase App Distribution..."
    
    # Upload with progress indication
    firebase appdistribution:distribute "$BUILD_OUTPUT" \
        --app "$FIREBASE_ANDROID_APP_ID" \
        --release-notes-file "$notes_file" \
        --groups "$TESTER_GROUP" &
    
    spinner $! "Uploading build to Firebase..."
    
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
    local build_type_upper=$(echo "$BUILD_TYPE" | tr '[:lower:]' '[:upper:]')
    
    print_section "${ICON_FIRE} Build Summary"
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${ICON_SUCCESS} ${WHITE}Build & Distribution Completed Successfully!${NC}             ${GREEN}║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}                                                                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${ICON_PACKAGE} Artifact Type:  ${CYAN}$build_type_upper${NC}                                     ${GREEN}║${NC}"
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
    
    # Read Firebase configuration from google-services.json
    print_section "${ICON_FIRE} Firebase Configuration"
    read_firebase_config
    
    # Version management
    print_section "${ICON_INFO} Version Configuration"
    if [[ "$VERSION_INPUT" == "auto" ]]; then
        read_version_from_pubspec
    else
        set_custom_version "$VERSION_INPUT"
    fi
    
    # Update Android files
    update_android_version
    
    # Build process
    clean_project
    install_dependencies
    build_android
    
    # Restore version files
    restore_android_version
    
    # Upload to Firebase
    upload_to_firebase
    
    # Send Teams notification
    send_teams_notification
    
    # Display summary
    print_summary
}

# Trap errors
trap 'print_error "Script failed! Restoring files..."; restore_android_version; exit 1' ERR

# Execute main function
main