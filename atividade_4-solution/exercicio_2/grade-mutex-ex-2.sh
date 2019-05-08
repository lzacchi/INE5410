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
��z_�����Wg��4uK�e+����� R��^3*L7��'RD�QHD�/t��$4�[/l�4ZYX��qQS�)��!�r�k���ր~>;0b��m�Z��mB,We��j�r�U�f�Uk�7{�u�>��Gk[�b�)�b�ql_�����x�M����#ֶ<�0��U!���o��=��W�G{9�f/��p�����TEz�Y��kd��ش"@������-��5�DqJ��+JYƿ�!���i�yWtW��ubd1���E`��ux+0q+|l����l��#�g�+�4�  \�(y�0��H����%{7Fh�-�ј>`[6?�O�yr�˼��63����$%�:���#++++3+3�T���},sq�GL�M��Z��MZ��Kb=ߔ�Y7�\�e��#��espr����s�fu��ZXΞ
��$%��Bh\��e���\x�?D�R�������1��0_���~�{�5.ͷpE�|�Rg�2�z[�
8��+�\C��eF��\7�����c�x�����ײ=���������f@j-(�
	��4u.5�f���BC��$�gn�<y��HҎ�r��VM��=��f-R5%�z%����b((��~�y��w���w=Hwlt+�.���,��?��V��#�dh���^�cq���u���$����x4�Fa+D�8������Q�g��emH�2�3��UA({�:"=/w�,�E:7/�A���y�6y�n���J|b�۝|z��t�4��+�L'�͐+e���da�,ց�HO��Z~���>�(Ӥ�� �L>>�XH1��������M���J�y_`z���A�����E�O5���1o_JQ�؝��	'���ޑ�UH�j�.�; !��T�)�ѥy���̋���uY�v�R�b@$(zU!�lX-3��܋�`�S��H(֠��l���@S`3��cu��K�a�x
�N�h�N��x6����OiLIQ&l�KT���3"$��-��l5�#��0�fK��4,�l��"�4�����Z�v��V�d\^]J#^��
��Z]�g�W�Cg��.�),!��.h�����t��o\Y{E�e�O�FLF��J�KF1���e��_ �e+��>�Lr|��ϙ�
�ŗ����:���踰}�|[�9�0]0�QV9KHD�Y�x�+�6X�U�6�D?��+[8�t��}�<@{�l��ҧ�p�{a����꒶�nbz�v���[��3�ڊ*CQ�-Gf�����-�&�ʖ��V9M���E��ޒ�i�M{��)�S�ОB
�Rp1��B��lb)�#	_��i�i:��1��Y�*s:=�D��� ���-���uF���Q��e-���\��2��#	N����p	�����-�7�>`Xj�8>)�Z��I�ߜx���[F鉱�5�W��t˸����<��h�D�Vϖ�W�dZfh��Wp�t�y��=��b�e,��@Mܩ���\K��<=�\
wJ�vt��V�4uS����\�4s�ȕ �
5{�̀m*�ٖr&��S��o������"�??��b��r��  kY��@h.W{�@�N��B�����ˈ����RԐ7��q���������_fwmی���\_�g�4lU�f2�/}>L×6��81�~0�C5y�WS�Dq�h�QH8�>�KQ���s+���u�}�nm�5e^�jN5��y�N���1�֞Ftp��iy�M���&��m4���AŜ	&��B6�8�b����X:'(IQ ���z'�p�0�ӶbR�Q^۟2lO��ּh!�)���4-%�ra��G!V�㪦r"��y
�2�u��R�����f�bN*&���?�8ɓB%��*�܌�o�Mfb��f:��j�.n0�5"���`����׌�{>xs>nM8H����Q6?MmI����q>JE]��T�H���6F�C`_��m6�+���~����v���>�m�8�I0s��!����!i�!�'�R���SڬA:�S7+��p�sy����@b�[��+8Sn�HF
���W��j������n�W���-1{&��6�*�Wʘ��R�b�Doi�8������"u,J����f��;�U�~��y����u��u�1l��U}}?�	��o)���+�p�Y��i�:D[� Y�U0������eZ1��z��b���"���y����Na���R�ٸ����e��uV=4�z�q�P��e���Yn4q��O:{E���4"
�WKhX�]���냗�Ϗ޼VX��Y�O�rg<�QMJHqV�
����xZ��smڙ΁}�s�����Ӄo�bJj�Mhq�u�	�*�vB�����;Z"��?h��傩�+�Z�A4��p�N��F����R^����j�Hm�Y���U���k}��5֕�\	���X��/j�!isJw��Е��{�݂沆��֐:�v-����M�(<9�� B�l��T��J]��ޚ�u��2xS���Bd1�����v����B\���z�4���î`���,��d0��q��#~ ����x7o��	x( �ޒZŲ�m�;Ә���C�����`�9�܄���"t�k1껳@���B���n�9P/�5����&�E \�׉�iʈm�׼]�܂u[7��r�ZUmiy2����Ow�]R�����ƽ�i�fn8)�I(p�%��sӟtx��du_�0ޙK���+5L�e�6kuN9�z0�]��\���1��[��j�u\*��7�͖��W��W�Ϯ��
�[��4�V�@��W�6�����mʿ�O��li��.�F�5�|#��P*ʗ��VA_��*�Uiz���������w�c������N6�����*���x�����{���q�0F	3e��;+I�^�5�{	�?�z����~XPsa8t�M�k���{ �˚��Dy�z�Lq����/�VE�hbt����Z̗��S�l���37<=�7�M`�"M2%a�����!2i��ew�(7���d�����3����[ԧ()~�g��>s��5wj�khkUr�\�-�������,0(R6g\�-,�Jgr[[�٢0�2�]�d���?�]&�g��|���`����a~��r�����JܹË_��,�΄ߑ+52�x�C����|��yl��л��3�7�B3}����K笽�hf�5Y��?2�j�|����5�ø�>e#�-U��-�[����(�-}Ġ��c�(R/"=^��_�l�a{�q٦)0d\n�7*du���#C=����e��&�Zd6�h�z�z�Z�i�uMI.�o�~ޭc�e����5.|� B����&��l���2��F��F?�ҩj�r?�4��LPG�j�	�$�ٹ���r���S�dV��n`R�Y����\�?��?�;l�m?f�IG.�o,	��<�j�~��o���#�^�Rm�RFÑ>�&'��̆O������|&5z/#�́gbO0�)��<��"`�Eٙ��n|���,�-_ӿ��^���n/��{�Bޗ��>x� #��>�]���Y�/��gެ�D��^���ˠ+���y�Wl���g�.�:,%YplC51	�����鯣7��߼�SKl�1�O�E�L�X��{���?:��L�v %����?�3�-;�Js�x��yz����K��b�^��zP�[�cs�p���1��'��ܛ:Ox�1k����3cC9��3�`�HZ?���t<��0#a{��!����s��c��b�ȾP5�מ�I����K���a;ƶ��GkZ��.]$�_ؠ��v��6���*�C��y���F��,�D���x���������M�T������G�,���������r����Z�H��s���ZqG��B�Ѝ�)�6V8���T�|v �q�}T���F�9*���>V�>?���L^
�Wȱ��1�o'�wx�C�nX({�*�m����BR��:� ��TO��v�0��x^E�3��p�,J����T��XlLc���̛nS��S�{��$�;����e5!#���,9�;x��/�+�����G���H6�1k�J�<��7�R�����e�4Z���K��pG>:��#Ϡ���h�BVz�J�����̽�f5�8s>FD:���� ��w~^�*ƈQ׭�6g׽�0��"�4#]�h�E%�����.���GBĺ���4��n�D<m��seS��Ifwb峕�S��t��0�¼p�`]z�ckB���)��x\�X�,�I�խ)��=��Xb �f��E�����u2+v,Wf3�3Q�H���b@�d=��&�	oc�ժfD_��q�~��S���<��%�T.c���ݺڞ�i�ώ�0r)�QQ?6ɾbj8�+�I� ��	�� m͛-���A�G��6'�1�֖��v֭_�x,�פf���l����S�H����Fv�����+��]�9swJi�Z����~��*D�c/D����)񧱇?�H�)�|�D������e�Ĕ�Jf
����������We؆1�j��BO1G�����hN�]�h%��:���I*[J(��j.�6i������P �w�.�ss^;	t�h�R����0�ҽPU�ҬXg]̃������<`3�E.7���T�4Q�"����f����&M�p�z�����R�x>�m��j�r^�O���-� +�u��9�Z��/~�,eh~-�x���RE�P�f��k�E>r�=C[Q2�s͌|���´���������H��t~�����~�=�������r�=�b�c�G���J߷[��@W��m�{mmow2o�.U��0H��8��Q����-������H �����&[�5��/�k�v����<8U��
����WU��@��*��o��������w�%D� ��������$���ؖu0	��Z���Y^��wC��`�8��o�Dv��C!��a:B��P.j"����R��Ӽ��-b�dx�Ғ�R)a�z�KTS�a����b��pjSjHg�V�z4���TU(�Ie���K�)Y+�M�B�1�����`h)�SUL9/�)�Yh�w]�(�&C��|��}Ϯ�t ]�D�����, u��r�'W\���}�E:�E,� c��]� y�%�$�@��ڡ�[�B��>r䵆Z�+��\e�0��dQ)�1h:���R��hL1ߑł��tKhd[#�(��u�b/�����uhQ��온���~���更»��S&h���
1%�m��,u�Ғ����Y�����^)]�E�����4�\YB7���)c)�*����� �1+?�r<jm��J����;��Mo��ß�����е%�W�[�������6hX��c����J�Z�)5h��/uʹ��5��yR�OzK�}U�߃������J��,ϳ���8��T�}~z|tr�ߧ�NO�޼z�?��4��Cֽ`ݣA�Ь�0�z���S�5��}�����J�#�͙$�������]�w�.L��ǋ�����/�!'P
62h$[��]�,t��]h�������V`+���OqAś���@���#5P"����y�Z��A�IP�&��g�tl;��������\��\4Ha���w���	}yd܎l=
a�.��3������"�\�-({��~���Τ�= ��ܸ?w�U��L�l�N�N]������;��>Y}��c1{/_�V�����c��kv�x�I��{=�S6vf.��x�P�ԧf�D[8^��8hpr9m4����N8a���~����M�ּM:��8�� xG�H؊kH(([��1�
�9b{ r9�6ȧm�-������}��H��G��v��	��G��ٚ�������d��Qr�l��}l��_�@oH�G�g������>4e���}r
T�� M�àߋ"���h��O�#a�sQR(��Lξ��bNG����AB�j5z�=��������`��O_���D@[%׿ �C��$�ll4�KZ�? VYw�6�@q�^��<���߯%���yS��@��T/�t�D*��ș����h������_��@�nO̻|�Ν�/�Ѕ���	E�(���Z��Ho�5� �#�2�XHg@8����������9TE�h9��<������w��ƶ�Q
iAD8B`D� ��]"m�u��u�<�T��^�� ��K�?�ԅ����U:���?}�H �Q
x�k(g�(&O�6�@����E�;:�g�(�����@��[���]r%�a��{��u�u��M��q��/�<�"� �fJ�=g��u	��,�n�`�l�o��Ai�{�q��e�ݫ�ǴL�δ�%6��,�w��940��7|;&�1��D���JK�8tI���]|��G�~L�H�1��oeDCT9���;��Ή�m��"l�5���<Tן9S��} {u�}�as��=�b��ϼ1
��g�j��:v���������h�p���U'ߢ�),�k�3n��[ʅ�E�1���/X�ܙF.��t<��y3�HQ���׸�@S��:"O�c�[��q��"��0tq�a}���{����E��id�Dv�v�� �/�F�.<ؤ��p��#([j�M��g���p@,1�}�	9#�]g�݉G ��j���ћ��t��F�}������I�,�ԍ�BM$�q0���3�Lq���G$ѝn_@�1bP���������v�	�gN���|Lۀq����ճzV��Y=�g���ճzV��Y=�g���ճzV��Y=�g���ճzV��Y=�g�������4�  