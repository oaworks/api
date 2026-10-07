#!/usr/bin/env bash

set -euo pipefail

TARGET_IP=""
TARGET_IP_CONFIRMED=0
IDENTITY_FILE=""
TEST_FILE=""
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FIXTURES_DIR="${SCRIPT_DIR}/../fixtures"

usage() {
	echo "Usage: $0 [-i|--ip <ip_address>] [-k|--key <private_key>] [-t|--test-file <filename>]"
	echo "  -i, --ip          Run on the specified droplet IP (as oaw, in ~/api)"
	echo "  -k, --key         SSH private key (prompted if omitted with --ip)"
	echo "  -t, --test-file   Existing test*.jsonl filename in ../fixtures (prompted if omitted or invalid)"
	exit "${1:-1}"
}

while [[ $# -gt 0 ]]; do
	case $1 in
		-i|--ip|-k|--key|-t|--test-file)
			if [ $# -lt 2 ] || [ -z "$2" ]; then
				echo "Error: $1 requires a value." >&2
				usage
			fi
			case $1 in
				-i|--ip) TARGET_IP="$2" ;;
				-k|--key) IDENTITY_FILE="$2" ;;
				-t|--test-file) TEST_FILE="$2" ;;
			esac
			shift 2
			;;
		--target-ip-confirmed)
			TARGET_IP_CONFIRMED=1
			shift
			;;
		-h|--help)
			usage 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage
			;;
	esac
done

if [ -z "$TARGET_IP" ] && [ "$TARGET_IP_CONFIRMED" -eq 0 ]; then
	read -r -p "Target VM IP address (leave blank to run tests locally): " TARGET_IP
fi

if [ -z "$TARGET_IP" ] && [ "$TARGET_IP_CONFIRMED" -eq 0 ]; then
	read -r -p "Run tests on this local machine? [y/N]: " RUN_LOCAL_CHOICE
	if [[ ! "${RUN_LOCAL_CHOICE:-N}" =~ ^[Yy]$ ]]; then
		echo "Cancelled. To run on a remote server, use -i/--ip <ip_address>."
		exit 0
	fi
fi

if [ -n "$TARGET_IP" ]; then
	SSH_OPTS=(-t -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
	if [ -z "$IDENTITY_FILE" ]; then
		IDENTITY_FILES=()
		for candidate in "$HOME"/.ssh/*; do
			[ -f "$candidate" ] || continue
			candidate_name="${candidate##*/}"
			case "$candidate_name" in
				*.pub|config|known_hosts|known_hosts.old|authorized_keys|authorized_keys2|environment) continue ;;
			esac
			IDENTITY_FILES+=("$candidate")
		done

		DEFAULT_IDENTITY_INDEX=""
		for preferred_name in id_ed25519 id_ecdsa id_rsa id_ed25519_sk id_ecdsa_sk; do
			for index in "${!IDENTITY_FILES[@]}"; do
				if [ "${IDENTITY_FILES[$index]##*/}" = "$preferred_name" ]; then
					DEFAULT_IDENTITY_INDEX="$index"
					break 2
				fi
			done
		done

		SUGGESTED_IDENTITY_FILE=""
		if [ -n "$DEFAULT_IDENTITY_INDEX" ]; then
			SUGGESTED_IDENTITY_FILE="${IDENTITY_FILES[$DEFAULT_IDENTITY_INDEX]}"
		fi
		if [ "${#IDENTITY_FILES[@]}" -gt 0 ]; then
			echo "Available local SSH private keys:"
			printf '  %s\n' "${IDENTITY_FILES[@]}"
		fi
		read -r -p "Path to SSH private key${SUGGESTED_IDENTITY_FILE:+ [$SUGGESTED_IDENTITY_FILE]}: " IDENTITY_FILE
		IDENTITY_FILE="${IDENTITY_FILE:-$SUGGESTED_IDENTITY_FILE}"
	fi

	case "$IDENTITY_FILE" in
		"~/"*) IDENTITY_FILE="$HOME/${IDENTITY_FILE:2}" ;;
	esac
	if [ -z "$IDENTITY_FILE" ] || [ ! -f "$IDENTITY_FILE" ]; then
		echo "Error: A valid SSH private key file path is required." >&2
		exit 1
	fi
	SSH_OPTS+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)

	RESULT_STAMP="$(date +%Y%m%d_%H%M%S)_${RANDOM}_${RANDOM}"
	printf -v REMOTE_COMMAND 'cd ~/api && RUN_TESTS_RESULT_STAMP=%q bash ./scripts/run_tests.sh --target-ip-confirmed' "$RESULT_STAMP"
	if [ -n "$TEST_FILE" ]; then
		printf -v REMOTE_COMMAND '%s --test-file %q' "$REMOTE_COMMAND" "$TEST_FILE"
	fi
	echo "Running run_tests.sh on droplet (${TARGET_IP})..."
	if ssh "${SSH_OPTS[@]}" "oaw@${TARGET_IP}" "$REMOTE_COMMAND"; then
		read -r -p "Save the remote test result on this local machine too? [y/N]: " SAVE_LOCAL_CHOICE
		if [[ "${SAVE_LOCAL_CHOICE:-N}" =~ ^[Yy]$ ]]; then
			LOCAL_RESULTS_DIR="${SCRIPT_DIR}/../results"
			mkdir -p "$LOCAL_RESULTS_DIR"
			SCP_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -i "$IDENTITY_FILE" -o IdentitiesOnly=yes)
			scp "${SCP_OPTS[@]}" "oaw@${TARGET_IP}:api/results/test*_${RESULT_STAMP}.json" "$LOCAL_RESULTS_DIR/"
			echo "Remote test result also saved to ${LOCAL_RESULTS_DIR}."
		fi
		exit 0
	else
		exit $?
	fi
fi

valid_test_file() {
	[[ "$1" == test*.jsonl && "$1" != */* ]] && [ -f "${FIXTURES_DIR}/$1" ]
}

if [ -n "$TEST_FILE" ] && ! valid_test_file "$TEST_FILE"; then
	echo "Test file '${TEST_FILE}' is not an existing test*.jsonl file in ${FIXTURES_DIR}. You must choose an existing suitable file."
	TEST_FILE=""
fi

if [ -z "$TEST_FILE" ]; then
	TEST_FILES=()
	for candidate in "$FIXTURES_DIR"/test*.jsonl; do
		[ -f "$candidate" ] || continue
		TEST_FILES+=("${candidate##*/}")
	done
	if [ "${#TEST_FILES[@]}" -eq 0 ]; then
		echo "No suitable test*.jsonl files found in ${FIXTURES_DIR}."
		echo "Run get_fixtures.sh first, or create a test*.jsonl file manually, then rerun this script."
		exit 1
	fi

	echo "Available test files:"
	for index in "${!TEST_FILES[@]}"; do
		printf '  [%d] %s\n' "$((index + 1))" "${TEST_FILES[$index]}"
	done
	while [ -z "$TEST_FILE" ]; do
		read -r -p "Choose a test file by number or filename: " TEST_CHOICE
		for index in "${!TEST_FILES[@]}"; do
			if [ "$TEST_CHOICE" = "$((index + 1))" ] || [ "$TEST_CHOICE" = "${TEST_FILES[$index]}" ]; then
				TEST_FILE="${TEST_FILES[$index]}"
				break
			fi
		done
		if ! valid_test_file "$TEST_FILE"; then
			echo "Please choose an existing test*.jsonl file from the list."
			TEST_FILE=""
		fi
	done
fi

echo "Running tests with ${TEST_FILE} at http://localhost:4000/test..."
if ! RESPONSE=$(curl -fsS --get --data-urlencode "sheet=${TEST_FILE}" http://localhost:4000/test); then
	echo "Error: The test request failed." >&2
	exit 1
fi

RESULTS_DIR="${SCRIPT_DIR}/../results"
mkdir -p "$RESULTS_DIR"
RESULT_FILE="${RESULTS_DIR}/${TEST_FILE%.jsonl}_${RUN_TESTS_RESULT_STAMP:-$(date +%Y%m%d_%H%M%S)}.json"
printf '%s\n' "$RESPONSE" > "$RESULT_FILE"
echo "Results saved to ${RESULT_FILE}."

echo "Response:"
if command -v jq >/dev/null 2>&1 && jq . <<< "$RESPONSE" 2>/dev/null; then
	:
else
	echo "$RESPONSE"
fi
