#!/bin/bash

##########################################################################################################################

# 通过Harbor提供的API来批量删除镜像，人工删除费时费力
# 经过测试发现，通过接口去删除时提供的是的标签，但实际上删除的时候通过的是镜像的IMAGE_ID
# 如果我把同一个镜像tag多次上传到harbor，通过API删除时，只需要提供其中一个标签，那么和这个镜像的IMAGE_ID相同的镜像都会删除


# docker版本：18.06-ce
# harbor版本：1.5.2

##########################################################################################################################



# harbor 安装目录
harbor_install_dir="/opt/harbor"

# 仓库地址
registry_url="https://192.168.1.106:443"

# 认证用户名密码
auth_user="admin"
auth_passwd="Harbor12345"

# 项目名称
project="test"


# Script run root
if [[ $UID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

# 检测仓库的可用性
function check_registry() {
  curl -k -s -u ${auth_user}:${auth_passwd} ${registry_url}/api/projects? > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "Connect to Harbor server ${registry_url} successfully!"
  else
    echo -e "Connect to Harbor server ${registry_url} failed!"
    exit 1
  fi
}


function fetch_image_name_version() {
  project_id=`curl -s -k -u "${auth_user}:${auth_passwd}" -X GET -H "Content-Type: application/json" "${registry_url}/api/projects?" |grep "${project}" -C 2 | grep "project_id" | awk '{print $2}'|awk -F "," '{print $1}'`
  image_name_list=$(curl -s -k -u "${auth_user}:${auth_passwd}" -X GET -H "Content-Type: application/json" "${registry_url}/api/repositories?project_id=${project_id}" | grep name | awk -F "\"" '{print $4}'|awk -F '/' '{print $2}')
    if [[ ${image_name_list} = "" ]]; then
    echo -e "No image found in ${registry_url}!"
    exit 1
  fi
  echo "All images in this project are:"
  echo "###############################"

  for image_name in ${image_name_list};
    do
      image_version_list=$(curl -s -k -u "${auth_user}:${auth_passwd}" -X GET -H "Content-Type: application/json" "${registry_url}/api/repositories/${project}%2F${image_name}/tags/" | grep  -w  '"name":' | awk -F "\"" '{print $4}')
      for t in $image_version_list;
      do
        echo "${image_name}:${t}"
      done
    done
}

# 删除镜像
function delete_image() {
  for n in ${images};
  do
    image_name=${n%%:*}
    image_version=${n##*:}
    i=1
    [[ "${image_name}" == "${image_version}" ]] && { image_version=latest; n="$n:latest"; }
    curl -k -s -u "${auth_user}:${auth_passwd}" -X DELETE -H "Content-Type: application/json" "${registry_url}/api/repositories/${project}%2F${image_name}/tags/${image_version}"
    echo "Deleting ${image_name}:${image_version}"
  done
}

# 垃圾回收，释放存储空间
function garbage_collect() {
  cd ${harbor_install_dir}
  docker-compose stop
  docker run -it --name gc --rm --volumes-from registry vmware/registry-photon:v2.6.2-v1.5.2 garbage-collect  /etc/registry/config.yml
  docker-compose start
}


case "$1" in
  "-h")
  echo
  echo "#默认查询所有 镜像名:版本号"
  echo "sh $0 -h                                                           #帮助"
  echo "sh $0 -d image_name1:image_version1 image_name2_image_version2     #删除"
  echo
  echo "#示例：删除 centos:6 centos:7 (镜像名:版本)"
  echo "sh $0 -d centos:6  centos:7"
  echo
;;
  "-d")
  images=${*/-d/}
  check_registry
  delete_image
  garbage_collect
;;
  "-q")
  check_registry
  fetch_image_name_version
;;
  *)
  echo "Error command"
;;
esac

