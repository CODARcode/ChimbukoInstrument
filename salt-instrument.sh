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

narg=$#
if [[ $narg != 1 ]]; then
    echo "Usage /path/to/salt-instrument.sh <source-directory>"
    exit
fi

orig_srcdir=$(readlink -f $1)
if [ ! -d ${orig_srcdir} ]; then
    echo "Must be a directory"
    exit
fi

srcdir="${orig_srcdir}_inst"

echo "Instrumenting within a copied directory, ${srcdir}"

if [ -e ${srcdir} ]; then
    echo "Output directory already exists, please move/remove it before continuing"
    exit
fi

cp -rd ${orig_srcdir} ${srcdir}

echo "Source directory ${srcdir}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
echo "Script resides at ${script_dir}"

container_id=$(docker run --rm -d  \
  -v "${srcdir}:/data" \
  -v "${script_dir}:/script" \
  paratools/salt-dev-with-salt \
  sleep infinity)

echo "Container is running at ${container_id}"

extensions=(cpp h hpp c cc)

declare -A languages
#languages["cpp"]="c++"
languages["h"]="c++"  #ambiguous
languages["hpp"]="c++"
#languages["c"]="c"

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
	exit
    fi

    intf="/data/${relf}"

    extra_args=()
    if [[ -v languages["$ext"] ]]; then
	extra_args+=("--lang=${languages[$ext]}")
    fi
   	

    docker exec  --user "$(id -u):$(id -g)" \
	   "$container_id" \
	   bash -lc '
intf=$1
shift
echo "Executing with file ${intf}"
echo "Extra arguments: $*"

cd "$(dirname -- "$intf")"
/opt/salt/bin/saltfm --config_file=/script/perfstubs_config_gpu.yaml "$@" "$intf" > /tmp/salt-inst-log 2>&1
ret=$?
if [ $ret == 1 ]; then
   echo "SALT-FM execution failed, log content:"
   cat /tmp/salt-inst-log
else
   echo "Success"
fi
' \
	   sh "$intf" "${extra_args[@]}"

    if [ -e ${absf_inst} ]; then
	echo "Replacing ${absf} with ${absf_inst}"
	mv ${absf_inst} ${absf}
    fi
    
done


docker kill ${container_id}

