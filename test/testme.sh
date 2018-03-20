#!/usr/bin/env bash

function perform_test() {
  # set up test location
  local TEST=${1}
  local LOGNAME=${2}
  
  cleanup_test ${TEST} 1
  cp -r test/envlink-test-template /tmp/envlink-test-${TEST}

  execute_test ${TEST} ${LOGNAME}
  EXIT_CODE=$?
  return ${EXIT_CODE}
}

function execute_test() {
  local TEST=${1}
  local LOGNAME=${2}

  exe/envlink -c test/envlink-${TEST}.yaml 2> /tmp/${LOGNAME}.err > /tmp/${LOGNAME}.out
  return $?
}

function cleanup_test() {
  if [[ "${2}" -eq 1 ]]; then
    # Remove everything, including previous tests' .out and .err files
    rm -rf /tmp/envlink-test-${1}*
  else
    # Keep .out and .err files for manual examination
    rm -rf /tmp/envlink-test-${1}
  fi
}

function verify_test() {
  local TEST=${1}
  local LOGNAME=${2}
  local TEST_OUTPUT=${3} # Output is intentionally less verbose if run a 2nd time
  local OK=0
  local EXPECTED_LINKS=()
  source test/expected/${TEST}
  if [[ -z ${EXPECTED_LINKS} ]]; then
    >&2 echo "In ${TEST} test: Failed to read expected links."
    return 1
  fi

  # Verify output
  if [[ ${TEST_OUTPUT} -eq 1 ]]; then
    for EXPECTED_LINE in "${EXPECTED_OUTPUT[@]}"; do
      grep -F "${EXPECTED_LINE}" /tmp/${LOGNAME}.out > /dev/null
      if [[ $? -ne 0 ]]; then
        OK=1
        >&2 echo "In ${TEST} test: expected output \"${EXPECTED_LINE}\" not generated."
      fi
    done
  fi

  # Verify generated links
  pushd /tmp/envlink-test-${TEST} > /dev/null
  find . -type l -printf "%p -> %l\n" > /tmp/${LOGNAME}.symlinks
  for MATCH in "${EXPECTED_LINKS[@]}"; do
    grep -F "${MATCH}" /tmp/${LOGNAME}.symlinks > /dev/null
    if [[ $? -ne 0 ]]; then
      OK=1
      >&2 echo "In ${TEST} test: expected link ${MATCH} not found."
    fi
  done
  popd > /dev/null

  return ${OK}
}

STANDARD_TESTS=('basic' 'symlink-update')
OK=0
for TEST in "${STANDARD_TESTS[@]}"; do
  LOGNAME="envlink-test-${TEST}"
  perform_test ${TEST} ${LOGNAME}
  EXIT_CODE=$?
  if [[ ${EXIT_CODE} -ne 0 ]]; then
    >&2 echo "In ${TEST} test: envlink threw errors."
    OK=1
  else
    verify_test ${TEST} ${LOGNAME} 1
    EXIT_CODE=$?
    if [[ ${EXIT_CODE} -ne 0 ]]; then
      OK=1
    else
      # Run envlink again to verify idemotency
      CURRENT_LINKS=$(cat /tmp/${LOGNAME}.symlinks)
      LOGNAME_2="envlink-test-{$TEST}.2"
      execute_test ${TEST} ${LOGNAME_2}
      EXIT_CODE=$?
      if [[ ${EXIT_CODE} -ne 0 ]]; then
        >&2 echo "In second run of ${TEST}: envlink threw errors"
        OK=1
      else
        verify_test ${TEST} ${LOGNAME_2} 0
        if [[ $(diff <(echo "${CURRENT_LINKS}") /tmp/${LOGNAME_2}.symlinks) != '' ]]; then
          >&2 echo "In second run of ${TEST}: not idempotent:"
          >&2 diff <(echo "${CURRENT_LINKS}") /tmp/${LOGNAME_2}.symlinks
          OK=1
        fi
      fi
    fi
  fi

  cleanup_test ${TEST} 0
done

exit ${OK}