#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
�      ��R�H�g}�Ah��ن���q-WBj�W#��.dɑd�"����>L�C��m_�c{�[�e��0��Y��s�sm٧�Em��_�aP@تT���U)į!,K�Ja���eK��Q.�����D����D,��y����??��q,�x����T)���$����.���m�̱I�E�_.���Y.o.A�q�χ�|�W��W��_�����~���y\;��jE�����nQi;.��E�٠�@�Q X.@(��P�����w b	z�MzrY�$>�Z���Hq�f���vZ����KxEzW��.ѹG���-"� A.�,s���j96��򨸗��w�)��_�	̍�G�0��d���4��������y��T�>�����U���hxk˂���/�~{����v������W���\��|��m4>�Z��(6F��ݬ9�^ځ�K��x���盓j\���/�).���=g8�-3��sF����qI��	��Ǣ���J���QL��) ��������!���g�N�w����<9;}�����j��×��*
w�m���S�|�%ߢ7y{`Y��`��]�Ͱ�,J��	�x��@�[��"
����kY�����@�F���*����P|֣��� ���K�=�<���L'���na��B�Q˒y��Qr'�C�ϥ��hU�)��M-���_Hb��`drA��(��6PăB����?��{��P�1|lA������,���$��՛ãj��ݹ� /������_�E���X�/�5�<ެ?����Ã����'?�L���1��Q�I�;w!��#�ZAJ�t8ထ�q�7����y���w\1X\���7��7���cn(��#���5���!��ψ�K�U��y��e:.f���d����h�mU0xț(�ކ"�m��R��ٶ�E��P�ץ���E�WO��0�#�k�L��^�fC&�"\�߾\�^$��.�ऎ������k�\�����6�N,Q�2�}U��%N���ۯ�|�������(��ځ:6�r<�E��ʈņk˘�*ŅC.�!��pQ�vx�u�C�Md��S��E� �ۛPW&c���"9�3ib�H#)�=����;E:�C���U�#���.��64Կ�vC� �髚�Q�j��6;#��Ʃ�q����0�9EB�@C�P0e��E���e��@�%�X��\���wV�*�%����`T�o��Zħ9���<����Q)%��R*���)`���-��b��G�%^��s��Y�p�>u�#
����Ŗ���5���/�:6XL1��8�X��*+����������#C���#v"e�X.���(����\1�O�5�ɜ�!F��f�*��eȄj�%6�j�"1�u�-{�o����6�r��`M
��0����J��)��'NoF�}�R�o�0���)�U��$g9%�!+-���d�(�39tr�P�L1z|ר4U#���)mb�ޒ�A�B (ٞت�8�
?uWf��Χ��uQ���Gw������N6S����۸k56�!fЩi�شHÆ�VQ=�z����xi5Y�X������\�mf��ޒ����Gg
j37a@����zwy��fK ��/W���]�P���W� $�"L�p�L������KP��U���:�'�?x� �}P=��>�{�x>w���Ro\l/,�p�a3ٜ�yg�7���^[Թ�^=��ƌ����B���������x:�/��W-|y��l?�KX�_�	�4O�s��x���)PfD�>���u����
���0fƪ8��!��c�G���l���Ў[u�w��)b?�����m�{=]�p�Q��1�O!|*P�� !Z'!����?)H�б��(guC���6}j��t,�$�~>��ՠ�F�:�E�1���x{�C��3]T�����b���@Čd��Qڝ��%��a�7��5��o1'+���.֔��ٕG���4��U��Djm A
��No���L�aAj�h�9���/��{���AT�6P�sq�p�bHK�6�G|����YV���'��9��r�,�ɨ�J��G�c��A�	'j�[n%n�kA--d�H������7����O~�bsb�~3�2"q���x3�k;L�(���R��4��U⣑K=c�ϹrQ]!$&�������⍄��2��^��Sn�wN�Wr�{��������Q�kާ�Z�!�����y���N_���l~�R��rk3�xF���ҹ�|������#����Mͮ�kD�Wp��P��o�S�"go<){c��i�����s����������ڗ��})��x���x����~���C�o�	�׎�&���)u��/:N���3Q�!&����P�G��Y�둌3�A��1S�I�ETG2(��R�j��hT���}�y��x��������t����#�5OB��aJ<����)�¼o��<��!�Z+Ԑ���\�y�i=�5�Ҡw�"+��Bxؓ��Dғ�V�=e'�����A����Q �<��"���9o�1e�,�/���tA�9�N�'g�����2��#u�h����i:g�!��~��{�'M�O�Dq��#N�>s\��RH!�RH!�RH!�RH!�RH!�RH!�RH!�RH!�'��㎳i P  