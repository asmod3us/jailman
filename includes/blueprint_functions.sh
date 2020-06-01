#!/usr/local/bin/bash
# shellcheck disable=SC1003

# shellcheck source=libstrict.sh
source "${SCRIPT_DIR}/includes/libstrict.sh"

initblueprint() {
	# as this function is called from blueprints we need to re-enable strict mode
	strict::mode

	local jail_name blueprint varlist linkblueprint linkvarlist value val linkvalue linkval
	jail_name=${1:?}

	blueprint=jail_${jail_name}_blueprint
	varlist=blueprint_${!blueprint}_vars

	for var in ${!varlist:-} ${global_jails_vars}
	do
		value="jail_${1}_$var"
		val=${!value:-}
		declare -g "${var}=${val}"

		if [[ "${var}" =~ ^link_.* ]];
		then
			linkblueprint=jail_${val}_blueprint
			linkvarlist=blueprint_${!linkblueprint}_vars
			for linkvar in ${!linkvarlist} ${global_jails_vars}
			do
				linkvalue="jail_${val}_${linkvar}"
				linkval=${!linkvalue:-}
				declare -g "${var}_${linkvar}=${linkval}"
			done
		fi
	done

	declare -g "jail_root=/mnt/${global_dataset_iocage}/jails/${jail_name}/root"
	declare -g "blueprint_dir=${SCRIPT_DIR}/blueprints/${!blueprint}"
	declare -g "includes_dir=${SCRIPT_DIR}/blueprints/${!blueprint}/includes"

	if [ -f "/mnt/${global_dataset_config}/${1}/INSTALLED" ]; then
	    echo "Reinstall detected..."
		declare -g reinstall="true"
	elif [ "$(ls -A "/mnt/${global_dataset_config}/${1}/")" ]; then
	    echo "ERROR, No valid install detected in config directory but files present"
		exit 1
	else
		echo "No reinstall flag detected, continuing normal install"
	fi

	if [ -z "${ip4_addr}" ]; then
		DEFAULT_IF=$(iocage exec "${jail_name}" route get default | awk '/interface/ {print $2}')
		declare -g "jail_ip=$(iocage exec "${jail_name}" ifconfig "$DEFAULT_IF" | awk '/inet/ { print $2 }')"
	else
		declare -g "jail_ip=${ip4_addr%/*}"
	fi
}
export -f initblueprint

cleanupblueprint() {
	# as this function is called from blueprints we need to re-enable strict mode
	strict::mode

	local jail_name=${1:?}
	local status_message=${2:-}

	link_traefik="jail_${jail_name}_link_traefik"
	link_traefik="${!link_traefik:-}"
	if [ -n "${link_traefik}" ]; then
		echo "removing remains..."
		rm -f /mnt/"${global_dataset_config}"/"${link_traefik}"/dynamic/"${jail_name}".toml
		rm -f /mnt/"${global_dataset_config}"/"${link_traefik}"/dynamic/"${jail_name}"_auth_basic.toml
		rm -f /mnt/"${global_dataset_config}"/"${link_traefik}"/dynamic/"${jail_name}"_auth_forward.toml
	fi
}
export -f cleanupblueprint

exitblueprint() {
	# as this function is called from blueprints we need to re-enable strict mode
	strict::mode
	local jail_name blueprint_name traefik_service_port traefik_includes traefik_status

	jail_name=${1:?}
	blueprint_name=jail_${jail_name}_blueprint
	blueprint_name="jail_${jail_name}_blueprint" 
	traefik_service_port="blueprint_${!blueprint_name}_traefik_service_port"
	traefik_service_port="${!traefik_service_port}"
	traefik_includes="${SCRIPT_DIR}/blueprints/traefik/includes"
	traefik_status=""

	# Check if the jail is compatible with Traefik and copy the right default-config for the job.
	if [ -z "${link_traefik}" ] || [ -z "${ip4_addr}" ]; then
		echo "Traefik-connection not enabled... Skipping connecting this jail to traefik"
	else
		echo "No custom traefik configuration found, using default..."
		cp "${traefik_includes}"/default.toml /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}".toml
		traefik_status="preinstalled"
	fi
fi

# If the default config requires post-processing (it always does except for user-custom config in /config), do the post processing.
if [ "${traefik_status}" = "preinstalled" ]; then
	# replace placeholder values.
	sed -i '' "s|placeholderdashboardhost|${domain_name//&/\\&}|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}".toml
	sed -i '' "s|placeholdername|${1//&/\\&}|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}".toml
	sed -i '' "s|placeholderurl|${jail_ip}:${traefik_service_port}|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}".toml
	# also replace auth related placeholders, because they can be part of custom config files
	sed -i '' "s|placeholderusers|${traefik_auth_basic//&/\\&}|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}".toml
	sed -i '' "s|placeholderauthforward|${traefik_auth_forward//&/\\&}|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}".toml
	if [ -n "${traefik_auth_forward}" ] && [ -n "${traefik_auth_basic}" ]; then 
		echo "cant setup traefik with both basic AND forward auth. Please pick one only."
	elif [ -n "${traefik_auth_basic}" ]; then 
		echo "Adding basic auth to Traefik for jail ${1}"
		users="$(sed 's/[^[:space:]]\{1,\}/"&"/g;s/ /,/g' <<<"${traefik_auth_basic}")"
		cp "${traefik_includes}"/default_auth_basic.toml /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}"_auth_basic.toml
		sed -i '' "s|placeholdername|${1//&/\\&}|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}"_auth_basic.toml
		sed -i '' "s|placeholderusers|${users//&/\\&}|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}"_auth_basic.toml
		mv /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}"_auth_basic.toml /mnt/"${global_dataset_config}"/"${link_traefik}"/dynamic/"${1}"_auth_basic.toml
		sed -i '' "s|\"retry\"|\"retry\",\"${1//&/\\&}-basic-auth\"|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}".toml
		traefik_status="success"
	elif [ -n "${traefik_auth_forward}" ]; then 
		echo "Adding forward auth to Traefik for jail ${1}"
		cp "${traefik_includes}"/default_auth_forward.toml /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}"_auth_forward.toml
		sed -i '' "s|placeholdername|${1//&/\\&}|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}"_auth_forward.toml
		sed -i '' "s|placeholderauthforward|${traefik_auth_forward//&/\\&}|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}"_auth_forward.toml
		mv /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}"_auth_forward.toml /mnt/"${global_dataset_config}"/"${link_traefik}"/dynamic/"${1}"_auth_forward.toml
		sed -i '' "s|\"retry\"|\"retry\",\"${1//&/\\&}-forward-auth\"|" /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}".toml
		traefik_status="success"
	else
		echo "No auth specified, setting up traefik without auth..."
		traefik_status="success"
	fi
	mv /mnt/"${global_dataset_config}"/"${link_traefik}"/temp/"${1}".toml /mnt/"${global_dataset_config}"/"${link_traefik}"/dynamic/"${1}".toml
fi

# Add a file to flag the jail is INSTALLED and thus trigger reinstall on next install
echo "DO NOT DELETE THIS FILE" >> "/mnt/${global_dataset_config}/${1}/INSTALLED"
echo "Jail $1 using blueprint ${!blueprint_name}, installed successfully."

# Pick the right success message to hint to user how to connect to the jail
if [ "${traefik_status}" = "success" ]; then
	echo "Your jail ${1} running ${!blueprint_name} is now accessible via Traefik at https://${domain_name}"
elif [[ -n "${2}" ]]; then
	echo " ${2}"
elif [ -n "${traefik_service_port}" ]; then
	echo "Your jail ${1} running ${!blueprint_name} is now accessible at http://${jail_ip}:${traefik_service_port}"
else
	echo "Please consult the wiki for instructions connecting to your newly installed jail"
fi


echo "DO NOT DELETE THIS FILE" >> "/mnt/${global_dataset_config}/${1}/INSTALLED"
echo "Jail $1 using blueprint ${!blueprint_name}, installed successfully."
if [[ ! "${2}" ]]; then
	echo "Please consult the wiki for instructions connecting to your newly installed jail"
else
	echo "${2}"
fi

}
export -f exitblueprint

