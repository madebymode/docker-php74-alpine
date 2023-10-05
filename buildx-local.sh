#!/bin/bash

DATE_CMD=date
if [[ "$(uname)" == "Darwin" ]]; then
    # If on macOS, check if gdate is available
    if command -v gdate > /dev/null; then
        DATE_CMD=gdate
    else
        echo "Error: GNU date (gdate) is not installed. Install it using Homebrew (brew install coreutils)."
        exit 1
    fi
fi


# Exit immediately if a command exits with a non-zero status
set -e

# Handle script termination gracefully
cleanup() {
    echo "Cleaning up..."
    docker context use default
    docker context rm builder
    exit
}

# Function to check when the image was last created locally
was_created_last_hour() {
    local image="$1"

    # Get the image creation time using docker inspect
    local timestamp=$(docker inspect --format '{{.Created}}' "$image")

    # Convert the timestamp to seconds
    local created_time=$($DATE_CMD --date="$timestamp" +%s)
    local current_time=$($DATE_CMD +%s)
    local one_hour_in_seconds=3600

    # Calculate the difference in time
    local time_diff=$((current_time - created_time))

    # If the time difference is less than an hour (3600 seconds), return 0 (true)
    if [ "$time_diff" -lt "$one_hour_in_seconds" ]; then
        return 0
    else
        return 1
    fi
}

trap cleanup SIGINT SIGTERM

docker context use default || true
docker context rm builder || true

docker context create builder

# Enable Docker experimental features
export DOCKER_CLI_EXPERIMENTAL=enabled

# Create a new builder instance
docker buildx create --use builder

# Variables
TYPES=("cli" "fpm")
PHP_VERSIONS=("7.1" "7.2" "7.4" "8.0" "8.1" "8.2")

for TYPE in "${TYPES[@]}"; do
    for VERSION in "${PHP_VERSIONS[@]}"; do
        DIR="${TYPE}/${VERSION}"
        if [[ -f "${DIR}/.env" ]]; then
            # Source environment variables from the .env file
            set -a
            source "${DIR}/.env"
            set +a

            TAG_NAME="mxmd/php:${PHP_VERSION}-${TYPE}"

            # Try to pull the image. If not available locally, this will ensure you have the latest metadata.
            docker pull "mxmd/php:${PHP_VERSION}-${TYPE}" || true

            if was_created_last_hour "mxmd/php:${PHP_VERSION}-${TYPE}"; then
                echo "Image mxmd/php:${PHP_VERSION}-${TYPE} was created within the last hour. Skipping build."
                continue
            fi

            docker buildx build \
              --push \
              --platform linux/amd64,linux/arm64 \
              --tag "${TAG_NAME}" \
              --build-arg PHP_VERSION="${PHP_VERSION}" \
              --build-arg ALPINE_VERSION="${ALPINE_VERSION}" \
              --build-arg ALPINE_IMAGE="alpine:${ALPINE_VERSION}" \
              --file "${DIR}/Dockerfile" \
              $TYPE/

        fi
    done
done

cleanup
