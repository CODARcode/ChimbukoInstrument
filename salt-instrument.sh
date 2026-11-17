#!/bin/bash
set -e

value_in_array() {
    local search="$1"
    shift
    local element
    for element; do
        [[ "$element" == "$search" ]] && return 0
    done
    return 1
}

tau_select_file=""
overwrite=""
instrument_inline=""
llvm_args_in=()
# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
	#Provide a TAU instrumentation file
        --tau-select-file=*)
            tau_select_file="${1#*=}"
            shift
            ;;
	#Overwrite existing instrumented files if exist (this will delete the existing instrumented file directory)
	--overwrite)
	    overwrite="TRUE"
	    shift
	    ;;
	--instrument-inline)
	    instrument_inline="TRUE"
	    shift
	    ;;
	--llvm-arg=*)
            llvm_args_in+=("${1#*=}")
            shift
            ;;	    	
        --*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Exactly one positional argument should remain
if [[ $# -ne 1 ]]; then
    echo "$@"
    echo "Usage: /path/to/salt-instrument.sh [--overwrite] [--tau_select_file=<filename>] <source-directory>"
    exit 1
fi

orig_srcdir=$(readlink -f "$1")
if [[ ! -d "$orig_srcdir" ]]; then
    echo "Must be a directory"
    exit 1
fi

srcdir="${orig_srcdir}_inst"

echo "Instrumenting within a copied directory, ${srcdir}"
if [ -e ${srcdir} ]; then
    if [ -n "${overwrite}" ]; then
	rm -rf ${srcdir}
    else
	echo "Output directory already exists, please move/remove it before continuing"
	exit 1
    fi
fi

cp -rd ${orig_srcdir} ${srcdir}

# put the select file inside the mounted directory
if [[ -n "$tau_select_file" ]]; then
    echo "TAU select file: $tau_select_file"
    cp ${tau_select_file} ${srcdir}/tau.select
    tau_select_file=/data/tau.select
fi

echo "Source directory ${srcdir}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
echo "Script resides at ${script_dir}"

container_id=$(docker run --rm -d  \
  -v "${srcdir}:/data" \
  -v "${script_dir}:/script" \
  paratools/salt-dev-with-salt \
  sleep infinity)

cleanup() {
    docker kill ${container_id}
}
trap cleanup EXIT


echo "Container is running at ${container_id}"

extensions=(cpp h hpp c cc cu hip)

declare -A languages
languages["hip"]="c++"
languages["h"]="c++"  #ambiguous
languages["hpp"]="c++"
languages["cu"]="c++"

find_args=()
for ext in "${extensions[@]}"; do
  find_args+=( -name "*.$ext" -o )
done
unset 'find_args[-1]'   # remove the final -o

mapfile -t files < <(
  find ${srcdir} -type f \( "${find_args[@]}" \)
)

for f in ${files[@]}; do
    absf=$(readlink -f ${f})   
    relf=$( echo $absf | sed "s|${srcdir}[\/]*||")
    ext=$(echo $relf | sed -E 's/.*\.([^\.]+)$/\1/')
    relf_inst=$(echo $relf | sed -E 's/(.*)\.([^\.]+)$/\1.inst.\2/')
    absf_inst="${srcdir}/${relf_inst}"
    
    #Skip .inst.<extension> files as already instrumented (if user chooses not to replace in-place)
    if [[ $relf =~ .*\.inst\.${ext} ]]; then
	continue
    fi
    
    echo "$absf : $relf : $ext : $absf_inst"

    if ! $(value_in_array "${ext}" "${extensions[@]}"); then
	echo "Extension ${ext} doesn't match expectation for file ${f}"
	exit 1
    fi

    intf="/data/${relf}"

    extra_args=()
    if [[ -v languages["$ext"] ]]; then
	extra_args+=("--lang=${languages[$ext]}")
    fi
    if [[ -n "$tau_select_file" ]]; then
	extra_args+=("--tau_select_file=${tau_select_file}")
    fi   
    if [ -n "${instrument_inline}" ]; then
	extra_args+=("--tau_instrument_inline")
    fi    

    nextra=${#extra_args[@]}

    llvm_args=(${llvm_args_in[@]})
    if [[ -v languages["$ext"] ]]; then
	llvm_args+=("-x ${languages[$ext]}")
    fi
    
    if [[ ${#llvm_args[@]} -gt 0 ]]; then
	llvm_args=("--" ${llvm_args[@]})
    fi    
    
    docker exec  --user "$(id -u):$(id -g)" \
	   "$container_id" \
	   bash -lc '
intf=$1
shift
nextra=$1
shift

extra_args=()
for ((i=0; i<${nextra}; i++))
do
  extra_args+=("$1")
  shift
done


echo "Executing with file ${intf}"
echo "Extra arguments: ${extra_args[@]}"
echo "LLVM arguments: $*"

cd "$(dirname -- "$intf")"
set -x
/opt/salt/bin/saltfm --tau_fabricate_unknown_types --config_file=/script/perfstubs_config_gpu.yaml "${extra_args[@]}" "$intf" "$@" > /tmp/salt-inst-log 2>&1
set +x
ret=$?
if [ $ret == 1 ]; then
   echo "SALT-FM execution failed, log content:"
   cat /tmp/salt-inst-log
else
   echo "Success"
   #cat /tmp/salt-inst-log
fi
' \
	   sh "$intf" "$nextra" "${extra_args[@]}" "${llvm_args[@]}"

    if [ -e ${absf_inst} ]; then
	echo "Replacing ${absf} with ${absf_inst}"
	mv ${absf_inst} ${absf}
    fi
    
done

