#!/bin/sh
#本脚本用于将epub分割为数个html文件，并进行必要的处理以便于导入tiddlywiki之中。
#索引页面的必有标签
INDEX_TAG="书籍渐进阅读"
#拆分页面的标签，额外包含书名
PAGE_TAG="?"
#最大拆分标题等级，由于html最大允许为h6,所以该变量使用大于6的值没有意义。
STOP_LEVEL=2
#文件最终的输出目录位置，默认为./
OUTPUT_PATH="./"
#测试依赖的命令是否存在
tr --version >/dev/null||exit
sed --version >/dev/null||exit
htmlq --version >/dev/null||exit
grep --version >/dev/null||exit
mktemp --version >/dev/null||exit
cat --version >/dev/null||exit
cut --version >/dev/null||exit
mkdir --version >/dev/null||exit

#变量临时目录
TMP_DIR="$(mktemp -dt splitXXXX)"
#当脚本收到停止运行的信号后，删除该临时目录
trap "rm -rf ${TMP_DIR};exit" 1 2 3 24
function old_print_title_string(){
    #接受从标准输入获取原始html,打印标题(h1,h2标签)，其中删除空格和制表符
    tr -d '\n'|htmlq 'h1,h2' --text|tr -d ' '|sed  's#　#_#g'
}

function old_print_split_linenum(){
    #传入要处理的文件的文件名，输出匹配grep字符串(默认是<h1和<h2)的行号。在输出序列和末尾额外添加1和$符号表示文档开头和末尾。
    echo -n '1 h1'
    cat ${1} |grep -En "<h[1-2]"|cut -f 1 -d ':'|tr '\n' ' '
    echo -n ' $'
}
function init_old(){
    #
    title_list="$(cat ${1} |print_title_string)"
    file_title="${2}"
    file_tags="${3}"
    if test ! -n ${file_title}
    then
	read -p file_title "请输入书名标题: "
    fi
    index_tid "${file_title}" "${INDEX_TAG} ${file_tags}" > ${file_title}.tid
    split_text "${1}" $(print_split_linenum "${1}")
}
function split_text_old(){
    #循环/分割，相对来说效率不高吧。其中传入的第一个参数为文件，后续为行号序列
    local import_file="${1}"
    shift 1
    while [ ! -z "${2}" ]
    do
	a=${1}
	b=${2}
	test "$b" = '$'||let b=b-1	   
	let c=c+1
	TITLE=$(echo "${title_list}"|sed -n ${c}p)
	tid_date "${file_title}/${TITLE}" "${file_title} ${PAGE_TAG}" "text/html" > ${TITLE}.html
	sed -n "${a},${b}p" $import_file >> ${TITLE}.html
	shift 1
    done
}
#-----------------------------------------------------------------------
function print_title_string(){
    #接受html文件,打印标题(h1,h2标签)，其中删除空格和制表符,并在最开头额外插入一个标题，用于分配给文件最开头，不属于任何同级其他标题的部分，默认为begin，然后把标题中的英文斜杠替换成中文斜杠(不太优雅就是了)
    echo "${3:-begin}"
    cat ${1}|tr -d '\n'|htmlq "h${2}" --text|tr -d ' '|sed  's#　#_#g'|sed 's#/#／#g'
}
function print_split_linenum(){
    #传入要处理的文件的文件名，输出匹配grep字符串(默认是<h1和<h2)的行号。在输出序列和末尾额外添加1和$符号表示文档开头和末尾。
    echo -n '1 '
    cat "${1}" |grep -En "<h${2}"|cut -f 1 -d ':'|tr '\n' ' '
    echo -n ' $'
}
function tid_date(){
    #生成一段tiddlywiki识别的data元数据，其中caption字段通过截取title字段自动得到。元数据与正文中间需要间隔空行
    echo "$@" >&2
    echo "caption: ${1#*/}"
    echo "revision: 0"
    echo "title: ${1}"
    echo "tags: ${2}"
    echo "type: ${3}"
    echo ''
}
function html_hook(){
    #接受管道输入，对输出进行一些预处理,比如说将在tid语法中具有特殊含义的`字符替换为字符实体&#96;
    sed 's/`/&#96;/g'
}
function split_line_text(){
    #适合递归的分割调用指令
    local import_file="${1}"
    local title_level="${2}"
    local parent_title="${3}"
    local title_num=0
    local output_path="${TMP_DIR}/${title_level}"
    local title_list="$(print_title_string "${import_file}" "${title_level}" "${parent_title}")"
    shift 3
    while [ ! -z "${2}" ]
    do
	local a=${1}
	local b=${2}
	test "$b" = '$'||local b=$((${b}-1))
        local title_num=$((${title_num}+1))
	title=$(echo "${title_list}"|sed -n ${title_num}p)
	if [ ! "${title_num}" -eq 1 ] #如果是该循环中第一个，则跳过目录生成，并非第一才会执行。
	then
	    split_count=$((${split_count}+1))
	    gen_toc "${title_level}" "${title}" "%${file_title}/${title}" >>${TOC_PATH}
	fi
	if [ "${title_level}" -eq "${STOP_LEVEL}" ] #如果标题级别和最大拆分级别一致，则更改输出目录，并写入元数据
	then
	    local output_path=${OUTPUT_PATH}
	    #标签取消上级目录，而改为主目录
	    #tid_date "${title}" "${parent_title} ${PAGE_TAG}" "text/vnd.tiddlywiki" > ${output_path}/${title}.html
	    tid_date "%${file_title}/${title}" "${file_title} ${PAGE_TAG}" "text/vnd.tiddlywiki" > ${output_path}/${title}.html
	fi
	mkdir -p ${output_path}
	sed -n "${a},${b}p" $import_file |html_hook >> ${output_path}/${title}.html
	echo -ne "正在处理 ${title}\r" >&2
	split_text_recursion "${output_path}/${title}.html" $((${title_level}+1)) ${title}
	shift 1
    done
}
function split_text_recursion(){
    #一个更改的函数，尝试通过递归进行分割。输入待拆分的文件名,参数1为需要拆分的文本，参数2为拆分目录的级别，参数3为父目录标题名称。
    local import_file="${1}"
    local title_level="${2}"
    local parent_title="${3}"
    if [ ${title_level} -le ${STOP_LEVEL} ]
    then
	split_line_text "${import_file}" "${title_level}" "${parent_title}" $(print_split_linenum "${import_file}" "${title_level}")
    fi
}
function index_tid(){
    #用于生成初始tid文件
    tid_date "${1}" "${2}" text/vnd.tiddlywiki
    #echo '<div class="tc-table-of-contents"><<toc-expandable "${1}" "sort[title]">></div>'
    echo "可以使用\`[[${1}]links[]!tag[!]]\`此筛选器用于钓鱼插件"
    echo ''
}
function gen_toc(){
    #生成目录
    printf "%0.s*" $(seq ${1})|tr -d '\n'
    echo " [[${2}|${3}]]"
    echo "${2}.html" >>${OUTPUT_PATH}/file-list.log
}
function init(){
    #第一个参数文件名，第二个参数文件标题，第三个参数，额外的主文件标签
    file_title="${2}"
    file_tags="${3}"
    TOC_PATH=${OUTPUT_PATH}/${file_title}.tid
    split_count=1
    if test ! -n ${file_title}
    then
	read -p file_title "请输入书名标题: "
    fi
    index_tid "${file_title}" "${INDEX_TAG} ${file_tags}" > ${TOC_PATH}
    gen_toc 1 "${file_title}" "%${file_title}/${file_title}" >> ${TOC_PATH}
    echo "${file_title}.tid" >>${OUTPUT_PATH}/file-list.log
    split_text_recursion "${1}" 1 "${file_title}"
}
init "${@}"
#rm -rf "${TMP_DIR}"
