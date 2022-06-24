#!/bin/bash

websocat --server-mode 127.0.42.1:8445 | while read -r line ; do 
  echo "received msg:"
  echo ${line}
  case $(echo "${line}" | jq '.cmd' -r) in
    store)
      url="$(echo "${line}" | jq '.url' -r)"
      title="$(echo "${line}" | jq '.title' -r)"
      tags="$(echo "${line}" | jq '.tags[]' -r)"
      tempfile="/tmp/dfs-temp-download"
      # echo "url   =${url}"
      # echo "title =${title}"
      # echo "tags  =${tags}"

      if curl --silent -o "${tempfile}" "${url}" ; then
        mime="$(file --mime-type --brief "${tempfile}")"

        echo "${tags}" | xargs --delimiter="\n" dfs add --mime "${mime}" --name "${title}" "${tempfile}"
      else
        echo "failed to download ${url}"
      fi
      ;;
    *)
      echo "unknown cmd"
      ;;
  esac
done