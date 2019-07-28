#!/usr/bin/env bash
declare -r APPLICATION_NAME='Clean Filter for GNU Bash Scripts'
# 林博仁 © 2019

# NOTE: ALWAYS PRINT MESSAGES TO STDERR as output to stdout will contaminate the input files when the program is operate in filter mode.

## Makes debuggers' life easier - Unofficial Bash Strict Mode
## BASHDOC: Shell Builtin Commands - Modifying Shell Behavior - The Set Builtin
set \
	-o errexit \
	-o errtrace \
	-o nounset \
	-o pipefail

## Runtime Dependencies Checking
declare\
	runtime_dependency_checking_result=still-pass\
	required_software

for required_command in \
	basename \
	dirname \
	realpath; do
	if ! command -v "${required_command}" &>/dev/null; then
		runtime_dependency_checking_result=fail

		case "${required_command}" in
			basename \
			|dirname \
			|realpath)
				required_software='GNU Coreutils'
				;;
			*)
				required_software="${required_command}"
				;;
		esac

		printf -- \
			'Error: This program requires "%s" to be installed and its executables in the executable searching paths.\n' \
			"${required_software}" \
			1>&2
		unset required_software
	fi
done; unset required_command required_software

if [ "${runtime_dependency_checking_result}" = fail ]; then
	printf --\
		'Error: Runtime dependency checking fail, the progrom cannot continue.\n' 1>&2
	exit 1
fi; unset runtime_dependency_checking_result

## Non-overridable Primitive Variables
## BASHDOC: Shell Variables » Bash Variables
## BASHDOC: Basic Shell Features » Shell Parameters » Special Parameters
if [ -v 'BASH_SOURCE[0]' ]; then
	RUNTIME_EXECUTABLE_PATH="$(realpath --strip "${BASH_SOURCE[0]}")"
	RUNTIME_EXECUTABLE_FILENAME="$(basename "${RUNTIME_EXECUTABLE_PATH}")"
	RUNTIME_EXECUTABLE_NAME="${RUNTIME_EXECUTABLE_FILENAME%.*}"
	RUNTIME_EXECUTABLE_DIRECTORY="$(dirname "${RUNTIME_EXECUTABLE_PATH}")"
	RUNTIME_COMMANDLINE_BASECOMMAND="${0}"
	# We intentionally leaves these variables for script developers
	# shellcheck disable=SC2034
	declare -r \
		RUNTIME_EXECUTABLE_PATH \
		RUNTIME_EXECUTABLE_FILENAME \
		RUNTIME_EXECUTABLE_NAME \
		RUNTIME_EXECUTABLE_DIRECTORY \
		RUNTIME_COMMANDLINE_BASECOMMAND
fi
declare -ar RUNTIME_COMMANDLINE_ARGUMENTS=("${@}")

## Global Variables
### Temporary file used in converter mode
### This parameter will be dropped in exit trap as we need to clean the temporary file
declare converter_intermediate_file

## init function: entrypoint of main program
## This function is called near the end of the file,
## with the script's command-line parameters as arguments
init(){
	local cleaner=bashbeautify
	local cleaner_basecommand=uninitialized
	# Referenced indirectly, false positive
	# shellcheck disable=SC2034
	local -a cleaner_command_arguments=()
	local flag_converter_mode=false
	local indentation_style=spaces
	local -i indentation_space_width=4
	local -a input_files=()

	if ! process_commandline_arguments \
			cleaner \
			flag_converter_mode \
			input_files \
			indentation_style \
			indentation_space_width; then
		printf -- \
			'Error: Invalid command-line parameters.\n' \
			1>&2

		# separate error message and help message
		printf '\n' \
			1>&2
		print_help
		exit 1
	fi

	if ! check_optional_dependencies \
		"${cleaner}" \
		cleaner_basecommand \
		cleaner_command_arguments \
		"${indentation_style}" \
		"${indentation_space_width}" \
		"${RUNTIME_EXECUTABLE_DIRECTORY}"; then
		printf -- \
			'Error: Optional dependencies not satisfied, the program cannot continue.\n' \
			1>&2
		exit 1
	fi

	case "${flag_converter_mode}" in
		false)
			# Filter mode
			printf -- \
				'%s: Cleaning GNU Bash script...\n' \
				"${APPLICATION_NAME}" \
				1>&2
			pass_over_filter\
				"${cleaner}" \
				"${cleaner_basecommand}" \
				cleaner_command_arguments
			;;
		true)
			converter_intermediate_file="$(
				mktemp\
					--tmpdir\
					--suffix=.v\
					"${APPLICATION_NAME}.XXXX"
			)"

			for input_file in "${input_files[@]}"; do
				printf -- \
					'%s: Cleaning "%s"...\n' \
					"${APPLICATION_NAME}" \
					"${input_file}" \
					1>&2
				pass_over_filter \
					"${cleaner}" \
					"${cleaner_basecommand}" \
					cleaner_command_arguments \
					<"${input_file}" \
					>"${converter_intermediate_file}"
				cp \
					--force \
					"${converter_intermediate_file}" \
					"${input_file}"
			done; unset input_file
			;;
		*)
			printf -- \
				"FATAL: Shouldn't be here, report bug.\\n" \
				1>&2
			exit 1
			;;
	esac

	exit 0
}; declare -fr init

print_help(){
	# shellcheck disable=SC2016
	# Backticks(`) in this context are Markdown code formatting, not command expansion
	# BASH_MANUAL: Basic Shell Features > Shell Commands > Compound Commands > Grouping Commands
	{
		printf '# Help Information for %s #\n' \
			"${APPLICATION_NAME}"
		printf '## Synopsis ##\n'
		printf '### Filter Mode(default) ###\n'
		printf '`cat _verilog_file_ | "%s" > _beautified_verilog_file_`\n' \
			"${RUNTIME_COMMANDLINE_BASECOMMAND}"
		printf '\n'
		printf '(Input should be provided through data redirection by shell facility, cleaned product is provided through stdout)\n'
		printf '\n'
		printf '### Converter Mode ###\n'
		printf '`"%s" --converter _verilog_file_ ...`\n' \
			"${RUNTIME_COMMANDLINE_BASECOMMAND}"
		printf '\n'
		printf '## Command-line Options ##\n'
		printf '### `--help` / `-h` ###\n'
		printf 'This message\n\n'

		printf '### `--debug` / `-d` ###\n'
		printf 'Enable debug mode\n\n'

		printf '### `--cleaner` / `-c` <name> ###\n'
		printf 'Select cleaner: `beautysh`(default), `shfmt`, `bashbeautify`\n\n'

		printf '### `--converter` / `-C` ###\n'
		printf 'Operate in converter mode instead of filter mode, accept non-option arguments as input files\n\n'

		printf '### `--indentation-style` ###\n'
		printf 'Specify style: `tabs`, `spaces`\n\n'

		printf '### `--indentation-spaces-width` ###\n'
		printf 'How many spaces comprises one level of indentation?  Default: 4\n\n'

		printf '### `--` ###\n'
		printf 'Signals that further command-line arguments are all input files\n\n'
	} 1>&2

	return 0
}; declare -fr print_help;

process_commandline_arguments() {
	local -n cleaner_ref="${1}"; shift
	local -n flag_converter_mode_ref="${1}"; shift
	local -n input_files_ref="${1}"; shift
	local -n indentation_style_ref="${1}"; shift
	# Indirect reference
	# shellcheck disable=SC2034
	local -n indentation_space_width_ref="${1}"

	if [ "${#RUNTIME_COMMANDLINE_ARGUMENTS[@]}" -eq 0 ]; then
		return 0
	fi

	# modifyable parameters for parsing by consuming
	local -a parameters=("${RUNTIME_COMMANDLINE_ARGUMENTS[@]}")

	# Normally we won't want debug traces to appear during parameter parsing, so we add this flag and defer its activation till returning(Y: Do debug)
	local enable_debug=N

	local \
		flag_indentation_style_specified=false \
		flag_indentation_space_width_specified=false

	while true; do
		if [ "${#parameters[@]}" -eq 0 ]; then
			break
		else
			case "${parameters[0]}" in
				--help\
				|-h)
					print_help;
					exit 0
					;;
				--debug\
				|-d)
					enable_debug=Y
					;;
				--cleaner\
				|-c)
					if [ "${#parameters[@]}" -eq 1 ]; then
						printf -- \
							'%s: Error: --cleaner requires 1 additional argument.\n' \
							"${FUNCNAME[0]}" \
							1>&2
						return 1
					fi
					cleaner_ref="${parameters[1]}"
					# shift array by 1 = unset 1st then repack
					unset 'parameters[0]'
					if [ "${#parameters[@]}" -ne 0 ]; then
						parameters=("${parameters[@]}")
					fi
					;;
				--converter\
				|-C)
					flag_converter_mode_ref=true
					;;
				--indentation-style*)
					flag_indentation_style_specified=true
					if test "${parameters[0]}" = --indentation-style; then
						if test "${#parameters[@]}" -eq 1; then
							printf -- \
								'%s: Error: %s option requires one argument!\n' \
								"${FUNCNAME[0]}" \
								"${parameters[0]}" \
								1>&2
							return 1
						fi
						indentation_style_ref="${parameters[1]}"
						# shift array by 1 = unset 1st then repack
						unset 'parameters[0]'
						if [ "${#parameters[@]}" -ne 0 ]; then
							parameters=("${parameters[@]}")
						fi
					else
						indentation_style_ref="$(
							cut \
								--delimiter== \
								--fields=2 \
								<<< "${parameters[0]}"
						)"
					fi
					;;
				--indentation-space-width*)
					flag_indentation_space_width_specified=true
					if test "${parameters[0]}" = --indentation-space-width; then
						if test "${#parameters[@]}" -eq 1; then
							printf -- \
								'%s: Error: %s option requires one argument!\n' \
								"${FUNCNAME[0]}" \
								"${parameters[0]}" \
								1>&2
							return 1
						fi
						indentation_space_width_ref="${parameters[1]}"
						# shift array by 1 = unset 1st then repack
						unset 'parameters[0]'
						if [ "${#parameters[@]}" -ne 0 ]; then
							parameters=("${parameters[@]}")
						fi
					else
						# Indirectly referenced
						# shellcheck disable=SC2034
						indentation_space_width_ref="$(
							cut \
								--delimiter== \
								--fields=2 \
								<<< "${parameters[0]}"
						)"
					fi
					;;
				--)
					# shift array by 1 = unset 1st then repack
					unset 'parameters[0]'
					if [ "${#parameters[@]}" -ne 0 ]; then
						parameters=("${parameters[@]}")
					fi

					input_files_ref=("${input_files_ref[@]}" "${parameters[@]}")

					# Break out loop as all arguments are processed
					break
					;;
				*)
					# Assuming converter mode
					input_files_ref+=("${parameters[0]}")
					;;
			esac
			# shift array by 1 = unset 1st then repack
			unset 'parameters[0]'
			if [ "${#parameters[@]}" -ne 0 ]; then
				parameters=("${parameters[@]}")
			fi
		fi
	done

	if test "${flag_indentation_style_specified}" = true \
		&& test "${flag_indentation_space_width_specified}" = true \
		&& test "${indentation_style_ref}" != spaces; then
		printf -- \
			'%s: Error: --indentation-space-width option can only specified if --indentation-style is spaces\n' \
			"${FUNCNAME[0]}" \
			1>&2
		return 1
	fi

	if test "${indentation_style_ref}" != spaces \
		&& test "${indentation_style_ref}" != tabs; then
		printf -- \
			'%s: Error: Invalid --indentation-style argument.\n' \
			"${FUNCNAME[@]}" \
			1>&2
		return 1
	fi

	if [ "${flag_converter_mode_ref}" = false ] && [ "${#input_files_ref[@]}" -ne 0 ]; then
		printf -- \
			'%s: Error: Only in --converter mode can have non-option arguments.\n' \
			"${FUNCNAME[0]}" \
			1>&2
		return 1
	fi

	if [ "${flag_converter_mode_ref}" = true ] && [ "${#input_files_ref[@]}" -eq 0 ]; then
		printf -- \
			'%s: Error: No input files are supplied.\n' \
			"${FUNCNAME[0]}" \
			1>&2
		return 1
	fi

	case "${cleaner_ref}" in
		bashbeautify\
		|beautysh\
		|shfmt)
			:
			;;
		*)
			printf -- \
				'%s: Error: --cleaner not supported.\n' \
				"${FUNCNAME[0]}" \
				1>&2
			return 1
			;;
	esac

	if [ "${enable_debug}" = Y ]; then
		trap 'trap_return "${FUNCNAME[0]}"' RETURN
		set -o xtrace
	fi
	return 0
}; declare -fr process_commandline_arguments

check_optional_dependencies(){
	local -r cleaner="${1}"; shift
	local -n cleaner_basecommand_ref="${1}"; shift
	local -n cleaner_command_arguments_ref="${1}"; shift
	local -r indentation_style="${1}"; shift
	local -ir indentation_space_width="${1}"; shift
	local -r runtime_executable_directory="${1}"

	case "${cleaner}" in
		bashbeautify)
			# Used in source scripts
			# shellcheck disable=SC2034
			declare -r SHC_PREFIX_DIR="${runtime_executable_directory}"
			# Out of scope
			# shellcheck source=/dev/null
			source "${runtime_executable_directory}/SOFTWARE_DIRECTORY_CONFIGURATION.source"
			# shellcheck source=/dev/null
			source "${SDC_CODE_FORMATTERS_DIR}/SOFTWARE_DIRECTORY_CONFIGURATION.source"
			cleaner_basecommand_ref="${SDC_BASHBEAUTIFY_DIR}/bashbeautify.py"
			case "${indentation_style}" in
				spaces)
					cleaner_command_arguments_ref+=(--tab-str ' ')
					cleaner_command_arguments_ref+=(--tab-size "${indentation_space_width}")
				;;
				tabs)
					cleaner_command_arguments_ref+=(--tab-str $'\t')
					cleaner_command_arguments_ref+=(--tab-size 1)
				;;
				*)
					return 1
				;;
			esac
			# stdin
			cleaner_command_arguments_ref+=(-)
			;;
		beautysh)
			cleaner_basecommand_ref='beautysh'
			case "${indentation_style}" in
				spaces)
					cleaner_command_arguments_ref+=(--indent-size "${indentation_space_width}")
				;;
				tabs)
					cleaner_command_arguments_ref+=(--tab)
				;;
				*)
					return 1
				;;
			esac
			# stdin
			cleaner_command_arguments_ref+=(--files -)
			;;
		shfmt)
			cleaner_basecommand_ref='shfmt'
			case "${indentation_style}" in
				spaces)
					cleaner_command_arguments_ref+=(-i "${indentation_space_width}")
				;;
				tabs)
					cleaner_command_arguments_ref+=(-i 0)
				;;
				*)
					return 1
				;;
			esac
			# FIXME: Style not customizable
			cleaner_command_arguments_ref+=(-bn -ci)
			;;
		*)
			printf -- \
				'%s: Error: Cleaner "%s" is not supported.\n' \
				"${FUNCNAME[0]}" \
				"${cleaner}" \
				1>&2
				return 2
			;;
	esac

	if ! command -v "${cleaner_basecommand_ref}" 1>/dev/null 2>&1; then
		printf -- \
			'%s: Error: Cleaner command "%s" is not found in your command search PATHs.\n' \
			"${FUNCNAME[0]}" \
			"${cleaner_basecommand_ref}" \
			1>&2
		return 1
	fi
	return 0
}; declare -fr check_optional_dependencies

pass_over_filter(){
	local -r cleaner="${1}"; shift
	local -r cleaner_basecommand="${1}"; shift
	# This is a name reference assignment, false positive
	# shellcheck disable=SC2178
	local -n cleaner_command_arguments_ref="${1}"

	"${cleaner_basecommand}" \
		"${cleaner_command_arguments_ref[@]}"

	return 0
}; declare -fr pass_over_filter

## Traps: Functions that are triggered when certain condition occurred
## Shell Builtin Commands » Bourne Shell Builtins » trap
trap_errexit(){
	printf 'An error occurred and the script is prematurely aborted\n' 1>&2
	return 0
}; declare -fr trap_errexit; trap trap_errexit ERR

trap_exit(){
	# Clean up temp files if available
	if test -v converter_intermediate_file; then
		if ! rm \
			"${converter_intermediate_file}"; then
			printf -- \
				'%s: Error: Unable to remove the temporary file.\n' \
				"${FUNCNAME[0]}" \
				1>&2
			return 1
		fi
		unset converter_intermediate_file
	fi
	return 0
}; declare -fr trap_exit; trap trap_exit EXIT

trap_return(){
	local returning_function="${1}"

	printf \
		'DEBUG: %s: returning from %s\n' \
		"${FUNCNAME[0]}" \
		"${returning_function}" \
		1>&2
}; declare -fr trap_return

trap_interrupt(){
	printf '\n' # Separate previous output
	printf \
		'Recieved SIGINT, script is interrupted.' \
		1>&2
	return 1
}; declare -fr trap_interrupt; trap trap_interrupt INT

init "${@}"

## This script is based on the GNU Bash Shell Script Template project
## https://github.com/Lin-Buo-Ren/GNU-Bash-Shell-Script-Template
## and is based on the following version:
## GNU_BASH_SHELL_SCRIPT_TEMPLATE_VERSION="v3.0.15"
## You may rebase your script to incorporate new features and fixes from the template
