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
�      �<�V�Ȳ�:��� ��`�[�f8	k�s����vkcKI!>f��<O��c��/RKn�@Y��$uW׭���o�h�R��_�ᛥ���e|�W�k�S��K�˫K�+u��7����c)I�0rB~p����M+�?����#��ߤܼ�����^R��/gT퍽N����;���ꋙ�_��H�n���y��<Z8u��S'��l��=l�/vv[��ҋ����z����s�����I�~��G��,!U����&��ԃ2BX�E�3��̎cV%aX&����8��k-/�k'�3<u� p��#G�wFfc�> D�Q9�i8C����:)������X��n��
���hL��Z=k������������{[��=n����vI��#\���8,�"��~�T?mV�i�O��m�~�(�X��y��瓲u|�3f�������nf���D�d
���f���d�����,} �'��	����')k�g�ӥ�Ǎ��4�_]���ˋ���������m4���n{mk��^{}v��ػ�{/�g�J/Z���[���.�����#��5ȟ�d�K?,x���.BfN�JGd�Q��QH��	����=�p�Gk�?�@+DxT���/}��Cꏣ
�������qC2��?�����-hye�'!K��L�ȵ���9Ï@�$��TU��܅��gٓ������F�Σ��KH�e�b��� Y���w�Ǧ�cq��WV���^�j�����-{�m�E ����F��"��'�1����þv��u֏���8b��	�O����Gӣ�{�t΋0)�T�� :gt���8����!��p<�l6�������KN�o�4Gan�_)���Ѩ
QSD����`�[/w����Y�, /Rm����������l}� h�`��#uR���g�:]��up$�W`c�7��8�ŷ����q87k�v�nY��$G����צ1�[ `���pQ�	�Y����,u�V�Gq�wqW�R0D�3}����&Ne[����/v���FjB�pdV�a���TcjQe>����AV@w� s���p�1f]Òs\�8�
� dccB\��F�V�@%>Iw���#%\>y�%Y���$'��G@�r.�<k�y�^�#����F�بF�ʰ�����iz4�F������!��|��`�1�����V��0�a�O�]�O�O���|���p��e�����ۇ�qJ�����:�T������A~ei)w�o�N�����{I3n�����������l����a�yko��ʶK3P���C�f\�3���9��Np6��H�~:�ṕ��Y�����v=7���w�2�{��,}��n���ij��L��!��[[�9^��Oa�g ��������?ÐvB-J/�	P`|܉؜f#�t�0�GN����?#�o���-A�[�����pIA}1E�#�?���v<*�(2���;m�ә�Ý�{��iv\q�]�Y!�"�k�
�n��/1�i��� RT�WD��bW��p������)E��}���T��~��lp�e��*�g߅O�9!}0��N�p��2{�L\�*W���U$4ꍜ ���*�*admTLe�x&��x6k�bZ�A�}����ͲX��^��r��)/<�w����Ν�(��˫�+�������p�vB0�(;�C�?9���t/��3H�=j��N��Լ�ɤrm�j`8�c��y�������!�N�p%�n������~�q#��i��0�j��F�����i��_��P�:
�KBR�t(��ᛝ=�ms�rjOT}�'*'�vsk�༑d5���إ�rT ��!L�>�Q�Ҡ,��S�����<}�� |�\�\��q��",�ؤ�\0*���ž'B�ϥ����7g'Q�����0~'kR���,]�c����w��Q�$�#ꥣa@���C_μ�z8"���G�B�e�T$����"ѳl�D���3�4k�h��PNġ�c23��J��.k�K���	���a�1�T"Y�=yI���������ii�ɵI5��1��
	(�h@��cY#F^Hem��C\v���3PX�a�f��(=#Q�����.�Z�5�r�2��7��	��:1\s*e0 �����}�l��s�yB���Y���J7M�g�B��qq�����Oº���c)�S��xB+���L`"J�b�Y�3��6⬎�Ͳ*�D ��)�q&��m�pP$]GL���H�~B���������MF�rW%�����5J��5Ti$I�������꼼�.GP<�A��(QA�+R	ǡ8��8�A �FT��x��a����:��P!1�y��U��ةI'�>�r���%a��}t�Z��d�I� ԮӰ�XV�_aH7��V�YjH2:oà��\jg�4��$�<����ؕx*���B�Wz�s�����S���Bfd0L�Y�d���Ӻ�=��9�'Q(����|r��\�T�'9���ٲZ!3��Y�3��Fcn������~{og�B�	+�d2X(�d���q@׌���L�;X�ˑ��/�K�" 
��TЄ���MB6`,��K@iX>u�	�N����к��NY�V�$Ƣ4���R�O/ͨ�T�Ĩͭ����8>]�9br��������ʚ��J��H�d� K��Gc�i�5�{�Yo�Yg��Y�QҼ�?�`L�'�ӻ��W�{/-��H�w;/pٺ��� �@B:���0���7�o�jS[�I���4��&}�f�p}�<�^]��)��D�<�������,C��_M�^�,��k	�Z�e���b��~�����v��5T/V�mu8��'#?�(�s�՟��-����(�4��ߥEƁ�ECs�3y^X�gž���f�Ź4�݈_�zuF_�{#��ʕ8�&<��m����e��5e����FM�z��*��;?vtt���b���b�4��7��:__������أQ{Z!K�O��\���l��%�ji�� ���g�5|<]n�c��*{ �����+��u����=�W��#d�?��	&S~:�g�ւ(�2�}/ѫ�� NGH�lȅ�T��Z�㱀��|8����9N6��,?3�dn�AX�N��AJ�6S��(��f
?���`�a�@�L�j]:�2��A�uU�qR��|)�̚�){Bu�\D	�h�2{r��@X�郆�ߴ��m�[m\~����6/Ega��q�hz䎨9Y��-�;�'��u�����0�O+؊�:��C���M�u�g�E��\]��\�[>���'
��J���Ǳ�U5�ؿ��,\�Q	+�i�0�I7.H��l�L�N`��K(��BfoT��4�B�F$����Ĥ{��+��*F�e�D]
�\U\\g��L&}L3�)y��P[7رH���n�7��=�)�WV&����Kҝ���	�� J9۩Jv�O��a�,ƀ/�d����w�F�(
*���^�E����Q�ȨP�~���;��u��k��C�Y!C
�����l����h&7��#�Z:v�;����Nn:N�	��+T�n�0e��7���+P�~�c��VC�)\�Ě¾t)���_�����u�O�HTq+Wׯ��B6��lЏ��#�"9]��@w�_j*( ���XjW0X�N���d��guRv��d�6�ש�ɀ�v�̷�Ȭza��i�CG�)ݑo���5��f:��;63(d�"?�������t�ZnhN�] �����m�Gq5��fE��sd���4[���];fi��>���]�|������nhL���K������/�߷O3d�F�9�'�Fto���q}\5���#�uB~��CZ�������ӱJۭvk��ڶ���g��C����?��>*�\��_��^;K���m�d��ǫ�Ub6P*%�m���˓Z����ֿ|��(�d���#c�`��l0�����T.���!� _F~�_p�^�N�x�/�����6��`�t�ĭ̚ V��~+e}ֵ4^nm]û��:��'<�{[d�z�4��Z����O���y[+mkU�����t��n���y�|]�o�^����Ö�~�Mk���Sb��?�yooه�o�Z�Z�i���d�i�#Ⱦ�"o{��T���h�?��x�����<���H���������v��_-g���#�536i��l&D��Tq��3�i�͌=}Q%�� 8J��f�J�PP9Q��hT��%ZS����贲$���-��C���YN�SG�n3wN��2���B�	��rz��K�� �ǈ�a��Y@��[D. �c��&�SIO,L�b
��{���roO�#�8����az���7q̅yHv"��
6p�!'A �qb���Xx!L5%�$�R�<B�XQߋ-W���.(j}�`�=3����	=���(X㮀�� T����ł���@eE7���1��5{x�g�1�����aR���i�IU/������_\B+����״���ŉ�_��0�������X�2bu��w��a��`�w§n'L�Sy8`�0���Ͻ*���#v�4��
�c��[���#مuC;��q�h���W`w��'��I�+���#tbЊ�ܣ��[uÅ���o �x�z=�!i��܇��-BET�F\@�I�_�\�"�0�\s�%�HʗS�9�a�5�3;w@���"2��P��yD��J��t�����B"'x���d�&2���xQG�`�߶[�ٍ���l4Y,��8;�-q��l��;�op�"Ņ����;驻y֔Tm{�͛�L*T%c�����6%��w/!�h�ˊ:x	�J��YJl� N���2bwl3?�u��ݶw7���?������xN�G-��}D��	z�����$׌J�GHD����!x�avN}~<��+�H o$h�����ߏ��;��Sy���I��@���5<��``�J�!��h��#.\��'�< �&�G������a���d�&�%�'�,ŧ��ev�X̿,��0���	�q�N�B9���^��M�.k`FZ��`�2�x\& ���nI�4�\�Յ�Y1X����Dz�6$�"d7�?aZ��6��DJ.n�j�7ח��s�9�Oi.�����oɶ\N/�j�n�ǲXn#�d7��E���S+ݾ��
���,(��,�ɠA�Dn��l���{+���(�؃�W�]:�i�LÐ�y-�$3:yc1S��l��M$E���^�1D�Ø��	#��&��g�6��ߐ��_��2�<�6��M(;��D��Mt+M�[�S`ܒe�-����Ҍ��K�,�bg�r��y`��%��;$���)���z?�f��&NN�1AV�����Ϙ �� �苢�kT/�w�S�ց�5�g��mz����9-+�1&0�ro��M��\X���l�;�f���^UB|�>��=���0ꃲU!��Ȥ[�*|�v�$���/�+ߘ�����.����H�߾G��G�x$�7�7x2.ܨ�X"��8ag�Q0�R��
���ba��n.`��t?���p8m���'V�@��T@T
��z_�����Wg��4uK�e+����� R��^3*L7��'RD�QHD�/t��$4�[/l�4ZYX��qQS�)��!�r�k���ր~>;0b��m�Z��mB,We��j�r�U�f�Uk�7{�u�>��Gk[�b�)�b�ql_�����x�M����#ֶ<�0��U!���o��=��W�G{9�f/��p�����TEz�Y��kd��ش"@������-��5�DqJ��+JYƿ�!���i�yWtW��ubd1���E`��ux+0q+|l������m��l���"k��$�nZ���J���l�����i5  I�	�����N3ӧL_��?�ݽ;�8|P���1������������3 U�E-��޵z�%3�ߥ%|�:%V�M��U}��١ӭ���<�6�g��4a�ي�Q~}n8{�,���8t�{��/�������ģ�Cr!��ڈ���=[��pE�����jϥƥ�V��!��Q���¾�t@���$�@�`ك�*��&��6���b?��bϧ{oN��>�R[AyS1�D@�.��d�R�`��]��Qhh4J���O�R�g�G��f��#����%�ɮ�Z�Ք૕���uCA]?mn�G��M|~׃t�F�b��E����q�)W@�ˇ�]���۶��v�ŷT�Ct�&�6� � ���Y���r�T.#Lv��T]�����!��D�̛W������J��r�H���2��9e��u��[&}j5>1��n9=E^��B�d�F�Љt3�2ط�n2�|��Z����l��~�u?�*ӡ��(�L>!�XH5���(hޗ�$,�o�-��}����Y��
�ʆ/�}�Q�����4�ݹJ���48��l�����p�= �OU;EUR#���eU_8�.��.aVj^�U�&���v0��^�=S&FB���f�̈́�
����kT]�$hg:)�Y:�6�Y��T24LcJ�2a�\РR�^P!��H,�f�x�ڇ�4m�gS�P�ygv���L>���Fj�5d��q}u�U9xm��(F���z��5���:s�vŞ���芦j�ތQ�����յW�^���a1j,�F~^0���g� ��
M�X���3($��?#��/��O�u�]�!4P��}.|�ɜ^�.��8���)$"�s�n��sl�j67�T?��S8�t��;�j}��b5آ��O���h��p3�K��F�+l����a�����E��V���l9�~̖Pn�5+6�d|��y>��Ԗ��ݴ\fsj�S��I.F�4(�RL,�x�����"e{�}1ARM���1���5 r���P��âN�=6�N�<�;�2i�
u�17�����H��$C?^ �娃6̨E/`K �����0��ʷ�a��4�) /���Qzb��cAE�U�/��2c=4����h��fj��{UM�eF��x�F��@W��I�1�S�`�����_���YN͋̥��^ظ�U�.��&M�T��11�:��\|z%h�b����7��b[*��+O��w�)9����Uv~���\��2�W�A@Ѳ�7.��R����d�E�����w�c�6��qC�L^'1j��W�~w0~�aܭm3r��6�Ca��6а�h�)X�Tz�/��[:sh&b��`Іkʈo���2��E��q}��j�;.��^��:��.�]_g%n*��ٜ�Ǘ�6x�a�c­�	�����0���=	LD��hp�ڣ�9&�b6��q��`��~�f�3wb��6�  }\Y� n ��s�6P G�}_{Yxhˋ��H�R�,���~jE>�f.'v�X��0�c�{�,��yoy@�}&@)椁�U���� �I��]�P��(.��2Y��j�t��_�.�@�|X�w��~t���`�ǭ(�2�Z=*�i� ���x�V�*O�QG�'�0���nlX���aTv[�[�ˣ��|���Ƚh���Cn�M��͇x�TKYRE���Y�uj�jV@J崏���?���^��n�L�	#M9�/��N��ż�W��<�O�_�hP�6���|��ې�^)�W��e����\���׶��3`Q+}=>Nsv��
�o?\Fq��1�8^��]�Fܴ��wB-�[�D.;K�J1\C�G�v�*UD[�`YӮ�mi�0{c��a�FL:j>��n���-�/k�w�j��S����T6nDc��}�rE+�5Ӄ�؎wumA/���N�+E�~T�U��`dDb���l�aA\v=d燯��ߜgX����&e˝�\F-9!�YKv�nC��i�\J��~p#Uw_��~�
Դ#hu�u�*��KТ��S����/���x�`��J��q�o(��c2��`�~���W�o�q��/r[m�/�~S軶�5�����JQ��}~��L��_��CRhJw��Y�JU�=�aCsEC�;�r��\�ũV=B���#��/f_@Ȟ9�d\�K_��[��m���|��PA!��Z��t����b����z�/4�kU��î��ͬ���L�8���1?�^�S��w�ԉ�x( �ޒ�$�Hl]:�����(�3���#s��)���U�j� b4�'Q�z]�N�Eh�^�k��۟��*.ͫ$�eĶ�k�.�Knżm��b��H�fm)y2����Ou�]P�iIƫ֣�P3w$J��|di�^��,�kf��ヹT��:�7B��D]׋f`3v�攣��p���}��j�7c���(���ƥ��}� ��ly{�����&�ºUnN�1)�+����ʆM�~GcF�y��_��r�lhJ�]*�T��ʍ��ZU�^�7*��ʞe@��M��6��1�{�C�Ar�7������������2���x�����{�j�������}�jҸWe��^��?�}���^��Sse8tg���©�z k����b���d-z�\d#+�U�c���>�֢���l�Um1�6q憧'��&�	�S�h��L�p��r6@B!�Ѡ�n�̍��@f�n�����>���)J�_i�E�!�O*,������V�/5l�<��L�d�!ce���na�V:���2S����0�uYu��:�w�,�ş���an�i������������S<�W���_����`W&��R�*D�u1Jjm���3]t������xc)4��7c<l�*A�TH��+�bfZ�ř�Q������\�8�+�S1R��1�B׾�}�_�T%���w��{E�E��w���-�l�t\�h
i����
�'�W<����-�����:��2;b����kէ���5����e��ٗ%�ű�]�\@�@��5E��҉���:u���F?�ZRux��,����m=���H�8(g/M����0�幤JѮ��J�x!~l<a;l�W�baAt4�bZ �Ɛ�H�����h�V���`$���a�2�Qp���Ù"?"3�Sm"/��眒
��1l��35'��m��[1��E��L֝;*qh�5����{qo��?��<Խ��A%��g�*��~�EA�{�싥��I��V6G�ds�$זL/�|�:�ɣ%Fy�[��'��>�9,gYp b#kz��������7�Cqj�m=g��?ߜ��1ֵ>c{Q���ˡc+��gQ�[P�x>��7��e�Ti`� q6��g:�;e��[�K�m�7X�E�v6u�H��T��,��O��i0v^Xx�1���cߙ���=�����:�VO�i,�����a�l��:`t7��u�q<�a�X��ϲ��y�Q:{a���<�}uqt�r�W�쏣+�/�bO�غur�?\[C����-�k��m���g[�O��La/��6������r3�ӌ
��k���������i�/H�<��M��'_���O����~�����;_��p��zwlaf�Z��89�t� �Ji�;����C`n4/������7�f K_��Mv�ĉO�&��K�[�-f�����S�E'��o?@�(�!H��=J����1��E��Ʌt$"�� A���W5n��Sߝ�[bVz#��n 3��tR<ȯ��-j�*�g�cA�R}��w�B�Ҁ�bbP�y�˸+��a[�қ[���M�9BW��^��`��k�mo��]�%�ZйP�ȼ�ҏ�EClT��y���1a��9(9O�A���+.��Z�#�C��}rn�D�iB�v���k>b���V�H���T���CM*��&K�Rd&h��-O�p��4����-?|����O���O�`��\�?������˳�\�Yo�������{g�oN��O��~���#ֻb��-�RL��Yg�s|fw�A�������7���w�8���:�c�z�U�_��E�֑���������qȬ���_�q?r��v�K�Dn�?��!� AM�ߧN��:�}�A��]mS�J�(�F�����G����ԇ6Y�AzN��"���
~!'�F|Xa������9���r{�\����!M���,�lʾ��#б�~��4��ڻ����q�pO����1��4R��}���B��B�%���6���ͦ;��OԔ^� &4П��ͩ�����͝��{='�E=�����ޕ?�����@�A�W縧�z��9��b�4{�k�s���u&>��xLp��f��	�!.��߁`q<�u~��\'�`+�� �0"�${�Kf�L�P;��	�a�A%�_(t�
�9f;Cv�#=�����a��^X�9��<>���>i"��@M9���v` Sg���d�Լ����c�-�T�u��ŧ��Д�v���p��pƠ[@7a �z�y#�C�`�-��@��]�3��8�$����aI����ʶ�'8~���F�� 2����&�; '�2T:����Ř~D��Z'�����-`���l��xjs:��	�R��P|� ��g<��o>Ƶ8�>7H���-)�K~�����WPaw�\9|b�>�Ġ��$� ��v;HJ�7�����0�P"��D*j��O)qI.s��/�J�Kʘ>N:�d��QƬ0���j��dA�#A4���O��}�ϰϣw�:���G�����/�ؗ��	G���#|%9�q��x����۳�u�_Y��E�RfY/�yCw{8�s��yA��u���@�G��U���h��5�*��`��k�ف�q^��x���Y�[��ei��yt�m�צ�7��'4M�θ�#6�<�Ƹ�7|k"��Nu�Dh��p�d�샤�_���E�^�E�	�:���A�(#.��10 ���yuI�����%;�z�;2k��9�8�V�>�:ra��������&�����3J�lQx
������ ��û�@�y~5��k4C�$��N-�6�8l���Ɗ��~�z���
c=
©�F��dNb�Pv�Gq\��!���'F9��_����Y����Y����j�~�.�M9?��$(N%���4����?���� �!d#$X&�J;�D� �}1�	$�f�R;15�k�����ۧ{��o�v�IȬV+%�2�7O[+����O�Bd:���������'��]F	.P�����U�*[ �U_]Y�uՃuu�$>&tf����ϭ�/��|���Y>�g�,��|���Y>��݀m� �  