KZipPath=$1
NeedToBuild=$2
ProjectDir=$3

source ~/.bash_profile
source ~/.bashrc
export KYTHE_KZIP_ENCODING=JSON
# Extraction
if [ "$NeedToBuild" = "-build" ]; then
	echo "start to build: ${ProjectDi}"
	cd $ProjectDir
	bazel --bazelrc=$KYTHE_RELEASE/extractors.bazelrc  build  --override_repository kythe_release=$KYTHE_RELEASE --explain "log.txt" --ui_event_filters=ERROR --repository_cache=  //...
	if [ $? -ne 0 ]; then
		touch error.flag
		exit
	fi
	mkdir -p $KZipPath
	# merge go kzip
	/opt/kythe/tools/kzip merge --recursive --encoding $KYTHE_KZIP_ENCODING --output  $KZipPath/go_merged.kzip bazel-out/k8-fastbuild/extra_actions/extract_kzip_go_extra_action
	/opt/kythe/tools/kzip info --input $KZipPath/go_merged.kzip | jq .
	# merge java kzip
	/opt/kythe/tools/kzip merge --recursive --encoding $KYTHE_KZIP_ENCODING --output  $KZipPath/java_merged.kzip bazel-out/k8-fastbuild/extra_actions/extract_kzip_java_extra_action
	/opt/kythe/tools/kzip info --input $KZipPath/java_merged.kzip | jq .
	# merge c++ kzip
	/opt/kythe/tools/kzip merge --recursive --encoding $KYTHE_KZIP_ENCODING --output  $KZipPath/cxx_merged.kzip bazel-out/k8-fastbuild/extra_actions/extract_kzip_cxx_extra_action
	/opt/kythe/tools/kzip info --input $KZipPath/cxx_merged.kzip | jq .
fi

# Index
cd $KZipPath
# step 1: generate entry from kzip
/opt/kythe/indexers/go_indexer  -continue $KZipPath/go_merged.kzip > go_entries
/opt/kythe/indexers/cxx_indexer --ignore_unimplemented $KZipPath/cxx_merged.kzip > cxx_entries
java -jar /opt/kythe/indexers/java_indexer.jar $KZipPath/java_merged.kzip  > java_entries
touch entries
cat go_entries >> entries
cat cxx_entries >> entries
cat java_entries >> entries
# step 2: Write entry stream to a GraphStore
/opt/kythe/tools/write_entries --graphstore leveldb:/tmp/gs < entries
# step 3: Covert GraphSore to nquads format
/opt/kythe/tools/triples --graphstore leveldb:/tmp/gs | gzip > kythe.nq.gz
