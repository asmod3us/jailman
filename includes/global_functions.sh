#!/usr/local/bin/bash
# shellcheck disable=SC1003

# shellcheck source=libstrict.sh
source "${SCRIPT_DIR}/includes/libstrict.sh"
strict::mode

# yml Parser function
# Based on https://gist.github.com/pkuczynski/8665367
#
# This function is very picky and complex. Ignore with shellcheck for now.
# shellcheck disable=SC2086,SC2155
parse_yaml() {
	local prefix=${2:-}
	local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
	sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
		-e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  "${1}" |
	awk -F$fs '{
		indent = length($1)/2;
		vname[indent] = $2;
		for (i in vname) {if (i > indent) {delete vname[i]}}
			if (length($3) > 0) {
				vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
				printf("export %s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
			}
	}'
}

# $1: config file
# $2: parsed config string to validate
validate_config() {
	file=${1}
	config=${2}
	if ! { sed -e s'/export //' | awk -F= '
		BEGIN {
			err = 0
		}
		$2 ~ /.*[[:space:]]"$/ {
			print "Key " $1 " has trailing whitespace: " $2 ""; err = 1
		}
		$2 ~ /^"[[:space:]].*/ {
			print "Key " $1 " has leading whitespace: " $2 ""; err = 1
		}
		END {
			exit err
		}'; } <<< "${config}"
	then
		echo "Error parsing ${file}. Please review the whitespace warnings above."
		exit 1;
	fi
}

# automatic update function
gitupdate() {
	local gitbranch  branch

	gitbranch=$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref -q HEAD)")
	branch=${gitbranch:-}

	if [ "$(git config --get remote.origin.url)" = "https://github.com/Ornias1993/jailman" ]
	then
		git remote set-url origin https://github.com/jailmanager/jailman
		echo "The repository has moved recently, we have pointed it to the right location."
		echo "Please invoke the script again."
		exit 1
	fi
	if [ -z "$branch" ] || [ "$branch" = "HEAD" ];
	then
		echo "Detatched or invalid GIT HEAD detected, please reinstall"
	else
		echo "checking for updates using Branch: $branch"
		git fetch > /dev/null 2>&1
		git update-index -q --refresh > /dev/null 2>&1
		CHANGED=$(git diff --name-only "$branch")
		if [ -n "$CHANGED" ];
		then
			echo "script requires update"
			git reset --hard > /dev/null 2>&1
			git pull > /dev/null 2>&1
			echo "script updated, please restart the script manually"
			exit 1
		else
			echo "script up-to-date"
		fi
	fi
}

jailcreate() {
	local jail  blueprint

	jail=${1:?}
	blueprint=${2:?}

	if [ -z "$jail" ] || [ -z "$blueprint" ]; then
		echo "jail and blueprint are required"
		exit 1
	fi

	echo "Checking config..."
	local blueprintpkgs blueprintports jailinterfaces jailip4 jailgateway jaildhcp setdhcp blueprintextraconf jailextraconf setextra reqvars reqvars

	blueprintpkgs="blueprint_${blueprint}_pkgs"
	blueprintports="blueprint_${blueprint}_ports"
	jailinterfaces="jail_${jail}_interfaces"
	jailip4="jail_${jail}_ip4_addr"
	jailgateway="jail_${jail}_gateway"
	jaildhcp="jail_${jail}_dhcp"
	setdhcp=${!jaildhcp}
	blueprintextraconf="blueprint_${blueprint}_custom_iocage"
	jailextraconf="jail_${jail}_custom_iocage"
	setextra="${!blueprintextraconf:-}${!jailextraconf:+ ${!jailextraconf}}"
	reqvars=blueprint_${blueprint}_reqvars
	reqvars="${!reqvars:-}${global_jails_reqvars:+ ${!global_vars_reqvars}}"

	for reqvar in $reqvars
	do
		varname=jail_${jail}_${reqvar}
		if [ -z "${!varname}" ]; then
			echo "$varname can't be empty"
			exit 1
		fi
	done

	if [ -z "${!jailinterfaces:-}" ]; then
		jailinterfaces="vnet0:bridge0"
	else
		jailinterfaces=${!jailinterfaces}
	fi

	if [ -z "${setdhcp}" ] && [ -z "${!jailip4}" ] && [ -z "${!jailgateway}" ]; then
		echo 'no network settings specified in config.yml, defaulting to dhcp="on"'
		setdhcp="on"
	fi

	echo "Creating jail for $jail"
	pkgs="$(sed 's/[^[:space:]]\{1,\}/"&"/g;s/ /,/g' <<<"${global_jails_pkgs:?} ${!blueprintpkgs}")"
	echo '{"pkgs":['"${pkgs}"']}' > /tmp/pkg.json
	if [ "${setdhcp}" == "on" ]
	then
		if ! iocage create -n "${jail}" -p /tmp/pkg.json -r "${global_jails_version:?}" interfaces="${jailinterfaces}" dhcp="on" vnet="on" allow_raw_sockets="1" boot="on" "${setextra}" -b
		then
			echo "Failed to create jail"
			exit 1
		fi
	else
		if ! iocage create -n "${jail}" -p /tmp/pkg.json -r "${global_jails_version}" interfaces="${jailinterfaces}" ip4_addr="vnet0|${!jailip4}" defaultrouter="${!jailgateway}" vnet="on" allow_raw_sockets="1" boot="on" "${setextra}" -b
		then
			echo "Failed to create jail"
			exit 1
		fi
	fi

	rm /tmp/pkg.json
	echo "creating jail config directory"
	createmount "${jail}" "${global_dataset_config}" || exit 1
	createmount "${jail}" "${global_dataset_config}"/"${jail}" /config || exit 1

	# Create and Mount portsnap
	createmount "${jail}" "${global_dataset_config}"/portsnap || exit 1
	createmount "${jail}" "${global_dataset_config}"/portsnap/db /var/db/portsnap || exit 1
	createmount "${jail}" "${global_dataset_config}"/portsnap/ports /usr/ports || exit 1
	if [ "${!blueprintports:-}" == "true" ]
	then
		echo "Mounting and fetching ports"
		iocage exec "${jail}" "if [ -z /usr/ports ]; then portsnap fetch extract; else portsnap auto; fi"
	else
		echo "Ports not enabled for blueprint, skipping"
	fi

	echo "Jail creation completed for ${jail}"
}

createmount() {
	# as this function is called from blueprints we need to re-enable strict mode
	strict::mode
	local jail dataset mountpoint fstab

	jail=${1:-}
	dataset=${2:-}
	mountpoint=${3:-}
	fstab=${4:-}

	if [ -z "${dataset}" ] ; then
		echo "ERROR: No Dataset specified to create and/or mount"
		exit 1
	else
		if [ ! -d "/mnt/${dataset}" ]; then
			echo "Dataset does not exist... Creating... ${dataset}"
			zfs create "${dataset}" || exit 1
		else
			echo "Dataset already exists, skipping creation of ${dataset}"
		fi

		if [ -n "${jail}" ] && [ -n "${mountpoint}" ]; then
			iocage exec "${jail}" mkdir -p "${mountpoint}"
			if [ -n "${fstab}" ]; then
				iocage fstab -a "${jail}" /mnt/"${dataset}" "${mountpoint}" "${fstab}" || exit 1
			else
				iocage fstab -a "${jail}" /mnt/"${dataset}" "${mountpoint}" nullfs rw 0 0 || exit 1
			fi
		else
			echo "No Jail Name or Mount target specified, not mounting dataset"
		fi

	fi
}
export -f createmount

