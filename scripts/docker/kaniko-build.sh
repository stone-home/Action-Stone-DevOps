# Runs in gcr.io/kaniko-project/executor:*-debug (busybox sh), started by
# .github/actions/docker-push as a docker:// step pod, from the DevOps repo
# cloned to .devops in the workspace. Not executable on purpose: the step
# passes it to /busybox/sh.
#
# The login goes to /kaniko/.docker (the image's DOCKER_CONFIG). Kaniko never
# snapshots or wipes /kaniko, so the login survives multi-stage builds and is
# never part of the pushed image.
set -eu

: "${REGISTRY:?}" "${REGISTRY_USER:?}" "${REGISTRY_PASSWORD:?}"
: "${BUILD_TAGS_FULL:?}" "${BUILD_CONTEXT:?}" "${BUILD_DOCKERFILE:?}"
ws="${GITHUB_WORKSPACE:-/github/workspace}"

if [ "$REGISTRY" = "ghcr" ]; then
  key="ghcr.io"
else
  key="https://index.docker.io/v1/"
fi

# umask only in this subshell: Kaniko and every RUN inherit the shell's umask,
# and 077 there made build files root-only (apt's _apt user could not read a
# keyring under /usr/share/keyrings: NO_PUBKEY).
# base64 "auth" instead of raw username/password: a token with " or \ would
# break the JSON.
(
  umask 077
  mkdir -p /kaniko/.docker
  auth=$(printf '%s:%s' "$REGISTRY_USER" "$REGISTRY_PASSWORD" | base64 | tr -d '\n')
  printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$key" "$auth" > /kaniko/.docker/config.json
)

# BUILD_TAGS_FULL: comma-separated full refs, e.g. stonebo/x:latest,stonebo/x:1.0
# Kaniko v1.24+: push is the default when --destination is set.
set -- --context="dir://${ws}/${BUILD_CONTEXT}" --dockerfile="${ws}/${BUILD_DOCKERFILE}"
ifs_save=$IFS
IFS=,
for ref in $BUILD_TAGS_FULL; do
  ref=$(echo "$ref" | tr -d '[:space:]')
  if [ -n "$ref" ]; then
    set -- "$@" --destination="$ref"
  fi
done
IFS=$ifs_save

exec /kaniko/executor "$@"