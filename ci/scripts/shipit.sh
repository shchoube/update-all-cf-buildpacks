#!/bin/bash

#
# ci/scripts/shipit
#
# Script for finalizing and packaging Helm chart
# and managing release notes
#
# author:  Dr Nic Williams <drnicwilliams@gmail.com>
# created: 2018-11-09

set -eu

header() {
	echo
	echo "###############################################"
	echo
	echo $*
	echo
}

: ${CHART_NAME:?required}
: ${REPO_ROOT:?required}
: ${VERSION_FROM:?required}
: ${RELEASE_ROOT:?required}
: ${REPO_OUT:?required}
: ${BRANCH:?required}
: ${GITHUB_OWNER:?required}
: ${GIT_EMAIL:?required}
: ${GIT_NAME:?required}
: ${NOTIFICATION_OUT:?required}
: ${HELM_REPO_URI:?required}
: ${HELM_REPO_USER:?required}
: ${HELM_REPO_PASS:?required}

: ${HELM_VERSION:=2.14.3}

if [[ ! -f ${VERSION_FROM} ]]; then
  echo >&2 "Version file (${VERSION_FROM}) not found.  Did you misconfigure Concourse?"
  exit 2
fi
VERSION=$(cat ${VERSION_FROM})
if [[ -z ${VERSION} ]]; then
  echo >&2 "Version file (${VERSION_FROM}) was empty.  Did you misconfigure Concourse?"
  exit 2
fi

if [[ ! -f ${REPO_ROOT}/ci/release_notes.md ]]; then
  echo >&2 "ci/release_notes.md not found.  Did you forget to write them?"
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

###############################################################

git clone ${REPO_ROOT} ${REPO_OUT}

(
cd ${REPO_OUT}
header "Bump version in Chart.yaml"
tmpfile=$(mktemp /tmp/chart-yaml.XXXX)
sed -e "s/^version:.*$/version: ${VERSION}/g" helm/${CHART_NAME}/Chart.yaml > $tmpfile
cp $tmpfile helm/${CHART_NAME}/Chart.yaml

# TODO: see https://github.com/starkandwayne/update-all-cf-buildpacks/issues/8
# 
# header "Bump docker image version in Values.yaml"
# tmpfile=$(mktemp /tmp/chart-yaml.XXXX)
# sed -e "s/^  tag:.*$/  tag: ${VERSION}/g" helm/${CHART_NAME}/values.yaml > $tmpfile
# cp $tmpfile helm/${CHART_NAME}/values.yaml

header "Update static install file"
helm template helm/update-all-cf-buildpacks -n "" > k8s-update-forever.yaml
)

header "Build helm chart"
mkdir -p ${RELEASE_ROOT}/artifacts
helm package ${REPO_OUT}/helm/${CHART_NAME} -d ${RELEASE_ROOT}/artifacts

helm repo add our-repo ${HELM_REPO_URI}

header "Uploading helm chart to chartmuseum at ${HELM_REPO_URI}"
artifact=$(ls ${RELEASE_ROOT}/artifacts/${CHART_NAME}*.tgz)
curl --data-binary "@${artifact}" \
  -u "${HELM_REPO_USER}:${HELM_REPO_PASS}" \
  ${HELM_REPO_URI}/api/charts

header "Update git repo with final release..."
if [[ -z $(git config --global user.email) ]]; then
  git config --global user.email "${GIT_EMAIL}"
fi
if [[ -z $(git config --global user.name) ]]; then
  git config --global user.name "${GIT_NAME}"
fi

echo "v${VERSION}"                 > ${RELEASE_ROOT}/tag
echo "v${VERSION}"                 > ${RELEASE_ROOT}/name
mv ${REPO_OUT}/ci/release_notes.md   ${RELEASE_ROOT}/notes.md

(
cd $REPO_OUT
git merge --no-edit ${BRANCH}
git add -A
git status
git commit -m "release v${VERSION}"
)

cat > ${NOTIFICATION_OUT:-notifications}/message <<EOS
New ${CHART_NAME} v${VERSION} released. <https://github.com/${GITHUB_OWNER}/${CHART_NAME}/releases/tag/v${VERSION}|Release notes>.
EOS