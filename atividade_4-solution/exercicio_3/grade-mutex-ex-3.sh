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
�      �<�V�ȲyEG��dl��-�3��5r�9�`����ڱ%�$����~���	��S��%�d ����^	�����]��7G4�N���/<�f�iuy�������A}qiyyuiu���Vo,���o�R��a��<p����M+�MQ�����o���������')���3���^'r}�ĝ��h���_YZ^y@j�C�8�����©�-�:a���`���a�~���Z�������륞��;�����/M��K��=rDf��?H��4Iԧ�ª@/�!�fv���*	��0�N�'���^ky�^;!/����S�9r�32#�!2d�ʩN��
T��(��AH�7��=��
�wS|�Th��Dc����Y�o�����.�j����m�w�����h�B�%ՖK�p����lv`X������S��Y��.���ۚ�,Q\���c����'e���3f�.׏�����N�/6�,�3���3��nK����ϣ�'Y�@	NR3\O�OR����K����i������ �����]$��_�l��o�vۛh�[�o��볋�����{�>�Tz�jm?���u}v��݇T=ie�A���� ]�a�,�py(B�0�p� P:"��2|�BR�O��l��)���|�������@�G��0���: �;��8��h�x]�7$�!��???�т�W&�dX��t�\�q�z�3��J"JI�QU� ߻P���#{�A�34݈�y��s	)��Z����$�C���6���o,N�������IR����`s�e�i�@�2��(�X�_�0�3���w�Wnb����~4Gl�`4��)8T��hz�vO���"L
7U�*�߄�]#�5Υ�#bA�}4"��yF�?�6�8"G�����Q��W��#g4�B�Q/"�E>س֋�={w}�<��T[}p6�/��2333[_3@��|���H�T�k�٧N�m���ؘ�h4<f�mF"r��͚����[�$2����k'�i�@%#5�FTb�bV�*�,K���Q��]�e���L(�}��S�ֻ�0��1�����"Y�UaX�c+՘�ZT�O/���y��<��A�&�z�Yװ�W-��!�ؘ�)F���U&P�O�]�b�H	��sI��;�2�I2�Ы�s ��|��ȱ�h��;6*�Q�4,n����`�M��fC,=hb��#�t�!9D���. ���,�c�5œ`����c�p<_�-,��hd#�(��a�����3p�N��8o�+4p�_YZ��������������ui����n��lo���v�������~iۥ(v�x�!J3����c�F]'8��o��\?��q8�@P�,�yvtj���E��;A�Ľ�j�>�n7ޅ���0���O�����À������ǧ0�� ��Y�o|�Q؟aH;����(0>�DlN��N�V��s'��m��7�B��疠ʭ��zPd8���>���"����3�f��ֻ�6��L��΋=��4;�8�ܮ��|�5`���Cٗ�4	��l� )*�+����+D��B�҈�Nq�q͔��оv�G*Yq?�|68�2�T�����'М�>{v����f��[&�P�+�T�*���FN��ZU�0�6*�2�V<��l<�5N1-Ə�҉>F�C��fY�Q���B9�����I���Vh�����ŕ���~���T8L;!�e��!؟��i:���A����ƞ��yC'�gj^��dR��6b50�1M�<����jg�y�t��C���SE
�p�z��q#��i��0�j��F�����i��_��P�:
�KBR�t(����=�ms�rjOT}�'*'�vsk�༑d5���إ�rT ��!L�>�Q�Ҡ,��S�ޛ��<}�� |�\�\��q��",�ؤ�\0*���ž'B�ϥ����7g'Q�����0~'kR���,]�c����w��Q�$�#ꥣa@���C_μ�z8"���G�B�e�T$����"ѳl�D���3�0k�h��PNġ�c23��J��.k�K���	���a�1�T"Y�=yI��������ii�ɵI5��1��
	(�h@��cY#F^Hem��B\v���3PX�a�f��(=#Q�%����.�Z�5�r�2��כ�	��:1\s*e0 �����}�l��s�yB�?�Y���R7M�g�B��qq�����Oº���c)�S��xB+���L`"J�b�Y�3��6⬎�Ͳ*�D ��)�q&��m�pP$]GL���H�~B�������MF�rW%�����5J��5Ti$I�������꼼�.GP<�A��(QA�+R	ǡ8��8�A �FT��x��a����:��P!1�y��U�_۩I'�>�r���a��}x�Z��d�I� ԮӰ�XV�_aH7��V�YjH2:oà�՜jg�4��$�<����ؕx*���B��z�s�����S���Bfd0L�Y�d���Ӻ�=��9��Q(����|r��\�T�%9���޲Z!3��Y�3��Fcn������~{og�B�	+�d2X(�d���q@׌���L�[X�ˑ��υK�" 
��TЄ���MB6`,��K@iX>u�	�N����к��NY�V�$Ƣ4���R�O/ͨ�T�Ĩͭ����8>]�9br����.���ʚ��J��H�d� K��Gc�i�5�{��Yo�Yg��Y�QҼ�?�`L����۽���{/,��H�;�qٺ��� �@B:���0���7�o�jS[�I���4��&}�f<w}�<
�^]��)��D�<�������,C��_N�^�,��k	�Z�e���b��~�����v��T/V�Mu8��'#?�(�s7՟������(�4��ߥEƁ�yCs�3y�[�'ž���f�Ź4�݈_�zuF_�{#��ʕ8�&<��m����e��5e����FM�z��*��;?vtt���b���b�4��7��:__����'O٣Q{R!K�O��\���t��%�ji�� �����5|<Yn�c��*{ ����'+��u����=����#d�?��	&S~:�g�ւ(�2�}/ѫ�� NGH�lȅ�T�OZ�㱀��|8����9N6��,?1�dn�AX�N��AJ�6S��(���f
?���`�a�@�L�j]:�2��A�uU�qR��|)�̚�){Bu�\D	�h�2{r��@X�郆�ߴ��m�m\~����6/Ega��q�hz䎨9YW�-�;�'��u�����0�O+؊�:��C���M�u�g�E�ེ@�*�|�	b�O�ٕ;�cU�j��I�Y���V�Ҳa�n\��u�4�����9P�
P0n5���ި��iV�@�Hb�	0��I�(o$VLMU������ �����L	�L��f�?R�0 5��n�c����?��o��u;{�S�-��L���ݟ����;�o��J�r�S��N����Y�_�r��+l�QT����"��!���Q'�6�#�wF�s꼇��0�f�)�������c7��܀���k��V��G�;��8&|�kc�Pa�}��C�D|�@�Y�a#[!�p!k
�¥�j�f~�"�w��W�?�"QōP\^�R
� �#�A?^��t��t��u�I,~	�����*�b�]}�`i;��Z�up/��I�;_����d_�N�&��13߮#���W�yL���tG�
L��|���4Z��̠���\��o�#��ij��9�vDZTlN�.��������Z�5�	�o��l��3ַ혥	ff�;����}�Q���>���CcJ�W_jL��[������}�!�4���!>	�0�Cx�5���㊨9t�}9���˿}�:4��+��'���U�n�[[�ֶ���>k�����AL�Qy�z]�<���)X���wl�t0 c�>^���R)1��m8d]����߈���點�@Y&K���Ӟ �f��lW�\�r����9�2�C��s`�u�w�	'E�w�A�0S��'ne֜ �*U�[)볮�A�bk�
�T,�9����8�{��E���xUa�wX����!46ok�m�ʶ��������u=���k�����u�~sز���n�5~}B����;��-�p���Vk�Q�=�=ݝ�8Mv�ٷQ��m�w����-M�����?��/��{�I7��~y���Ν����5yȡ�f�&-�C�̈́Q�*��AuF?�µ���/J��tG��,U�
*'�P��3]�Dkj>���V�D`���!�eyh��1��z�(�a��m�ΩY&_q^(;�YyA.@/�q����$�Q<�>�h�yK���t�<ڤs*鉅�\La�`��S���w���:88L���w&��0�N$TA�N8�$�;�@���/����Ҁ�T��GH�K#�;��*4��eE��!��gf6����k����J�6�X��� �L��ZxBv8&��f����l<�~�1>L*��46��E?S|��%����vnM�a�_���5j��;I�O�e(#Vw��x7���
�'|�v�$:�����k��ܫb��:b��@��a�P8�+�e�?0�]X7�����&�8|v�{�h�t����=B'�(�=j��U7\��������V��}8��� TD�h�T�T���5*R	��5'\R��|9��S�QvZC:�s�i��(�!s:OA %��ATZ�\J'[�=���\H�������D��>� /���՛v������A��������g�̖�����(�Q\^ͼ����gMIն7_��m��Ae1P2�ix�kS��|��&�������Ϡ�H���&�$�*�z�!#vw�6��Q��m{w����^��?��sj?h����#��N�3���p''�fTJ?@"�ͬ�� �s���?\*Gx#Aä.ި��~������sE�N��-E���?`�T
eaFs�q�R][>q��4�<�D����&�7y,Y8Q`)>��,�c�b�e�l��Y��HO��3�p��ʡ� ����u�R^hBtY3�be. �)��0؅vKB�!�*�.�ϊ��Tm�'��!!���	�:0�9ol'�Prq�W;���d7����Js�������|C��rzaW+��p�>��rY%���,
�H��Z��M$Wh�gA��me�N�$r�d[,e�[��=G!��b��qLd�X�t�+	'�������|d�En")�L��ʌ!�ƴ�`(�MA��a$�8K��M��l���W�!�)��5nB��&����[i�߂���(oI���f<_�fa;�����+D-�d�!�N9��ջ�4�E4qr�P�	��e�Wl~Ƥ ���W@_e]�za�s��7<����8+o���_5�iYэ1��YW�x]��h�?��j�Wfc�؉4�������i�=�#H�q�>([��.�L�U�2�'o�N�;<���ina���Yojj�D`��{$�$�F�x���'�܍��%�v�S*Ś����-&����O�cKlA
��Fʪ�pb�dlND�0�x��U�����}u�HLS��Y�Rha0Q8J�P!
"�L`���t�~~"ED��D�B�OBc����I����;5���(�!�F��n�'��#�������&�rU�۫f/�_�h�^��~��[�����*&ݐ�/V����(������T�z��>8bm��	��`X��/�����/u}���i��
�����IU�w�UX�F��M+�o�9�|���XCpM�DO���e�+�Na��V�wEw�^�!F�>�YF;�Q�����S����5En$�<����n<ػ�=�,�Y.��f|/!��iIm}�wg̏���u�=9��^�c��U%UI��f�@�;�����������*�׼��w|	�Z�Ԓ����>w����Ϣ>y����Vl�p�M�����0{l��(�23�=U�Ij����=p킗��Rm�op���!>��Im�MN���m��pE�����jϥƥ�V��!��Q���¾�t@��$׶���-UV�Llm*�1Q�)�~R�ŞO�wߜ����R[AyS1�X@�"��d�R/H�.N�(44�H�$p������!��+�H��h�{�VQ-�jJ��JXGݺ���������B������ ݱѭ��x��.0q����!fO�9(�v���v�ŷT�t�&��v���Y���r�T.#Lv��T]�����!��D�̛W������J��r�H���2��9e��u��[&}j5>1��^9=E^�������
h��f�7e���d��,���Jϧ�By���~�U�CQ�a��||���j).��׼/�IX"�i[*���;/�(U�_��T�N\���7�ݾJ�h�hp�=9�	7V�{ 2쟪v���Ft)�=*6˪�pv��=¬Լ0	�^M%V�ƌ>@{A�<�L��bz�F�	)46y?VϨ�4�I��tRF�t�mĳ/7�dh��Ɣe�V9�A��-��B���Xt�V�:��3ivE�M�BQ���AD��2��_��Eh׈�Th��եV1�ു.3��_������f���{
C��"�+���z3F���b�W�^�{�S<�Ĩ� �y�(����P�+4�b�n��A!�\��s���~�%�����k4���T�υo�b2��f;Ϊ�m
�H:��[a��[����:�Ok��N"]v�ξZ��X�(h��d�(=�2�V��꒷����
�]��tTmp��v�"Lh+jEi��
�sfK(�Ԛ[2>+�<WٶՖ��ݴ�\fsj�S��q.F�4(�RL��x�����"e{�}>ARM���1���5 r���P��âN�=6�N�<�;�2i�
u�17�����H��8�}7��娃6̨E/`K �����0�Oʷ�a����) /���Qzb��cAE�U�/��2c=4�}��h����R�����l���3]��&��PZL��7Pcw�&n�&��rj��c.�����M�rt�%7l0i��ʹ���֩���+A���af\�"�m�dү< �ys�䜮6�W���	�s���P_�E�O�8BK�ڋ�Er�{�/�߱�Y�x���e3y�Ĩ9__,x������q����!,O����y�@�V�m�`�R���u��L�x��v�)#��c$��L#�J�i�I��k�5���{q�긮��ve�����gs�Þ\v�d�݃��	��&��k�N��l���%0!n��ohS(f�1��� ���!H`��E�ǒȞ�@IU �>.,�
�
7����9m(�����~(��,<��EyM���y)yP
[U?
�"W3�;h,�Sױ���L�b���< �>�s�@���O\���
�ҮM��|��,�R5Q�����w�p���,ڻ?}�?�G�7��V��|�k��ӴV��غx�V4VU�^���.�0���n�6�g��0*�-ԭ���k	|>��q��0�������C��C<N
��,�"�Cެ�:�S5+��rڇSy��I	��~�bn7H�҄�&��T�N��b^�+�H�'�A4�Mb�t���m�U���+��2E�^Q�q���k������.C��i��0W�����0
�?fǫ����c؈������N�~K��egi])�kȝ�����Z堊h�"kv+h[Z/��؋jX�S����O-�~E(b��˚���hW&m.z.՟��X �}_�\�Jg���!���C][�Kk��g��J���zU�?��+�%C4,�ˮGl������ћ���m��F�r�˨%'�8k����m(�W�7����OK��Nc���˝��AR��v��nAP��}	Z4�~�����Ac/�=\)w�<����;!#��'Z�ye�Vw��"����7��k;^s�{�a����J��7�%�>����BS���D�JW���.4W4D8XCk�8ժGh6|�����ٳ!GS���u�kx�׵�Y���!p*(D�Y�9���|$���G�����]��0�v���lf���&`*�q�N��� ����ݼ�GR'�ᡀWxKj��"�uiO���a<`V��1�TsS6�«�ծAĨ�a�z]�N�yh�^�k���_��U(\�I�)ʈm�ײ]�܊y�6��|�Z��R�d`��� ;�z�
��W�'d�f�H�*�uI}����
�Y�����s�0�Su�o��������f��)G]�Ⴙ������o8�2Bq�Q6��KE]��A~���>�J����M�_�u�ܜbcR�W�=�Օ�R��ƌr�Ϳ�O�.�Д��T�ޙ��7
��|�oT�3�=ˀzS��m�oc��<����o��e��Q���9�x���9��/������9��F+��l�x5iܫ�fs/a��tf�c����(��2��J�k���z k����b���d-z�\d5+�U�c���>�֢���l�Um1�U6�bq憧'����	�S�h��L�t�r���B�����e27�s�� 2ct����g�	��OQR�J.21|�Paiw�Ԫ�ॆ�2Ϲ�1`�XY���[���䦶�Ԣ0�:�j]V�d�����]&���O���07�4�����fi�_>���㩽�W����W��˸2�w�JV!��s�PRk��ĽLt�yW�IA��Rh��o�x��U�`����W�̴ �3�G!@<'_���sE�Юd�O�Hq��,
]���-�ʾ�*Q,�Ǡ��s�(r/"5^��_�n�cCs�qݢ)0�]n�6*t��^q�G�z�O@��W�����������~ �U�F^W��J�V��Z0f_��Ώ]���"j�a(��e�c%�-ש3p�D��0��ג����<R��@�����lI�����r����`)�� Q�K�����/��l���],,��\L �	}��*�-Z����#	/�r��e���p�ȏ�L�T��K=}�)��{�<Ss��O�ܖ���]�Y�d�9%-�����9�[/�-����⇺�W>��}��Yy��zI�{��������|��v�kv|m��B�u�þ<Zb��_��?��Y⺬o��qd�mY����\^��:zsv��l$N-���lm��ւt2���l7����tl���,�v%����?����R���U�؎�4�?=߶�){��]Rlu��(����Ԇ"aR!�1X�?���~a�}Ƭ#�L\;`�r@�m�X��ב�x,Oc�ء�0#e[��mFw��K��c��c�Ⱦ�j"Hg��i��:>9zy�������(�"P9��W�@�b��^��������Ɛ�X�{��10��>�9�_�p��6���2M�2�z�-�S7"�a7��g�M������Џ�o�������C] ۴��r�t�������y��)��Ū�ʚ�`v�>u�sa�WowX5ٮh!�����j����)8j�O��>����|�(�_ﲧ�6T�3���k��S��ì�����,e�H.�mc1ùt�Y[c�v�r��Ӂ�~���2[�TO,��b�2��^0��5�x� -�)s!�]�_/�W���<J=m������X^�矙 }�i�����@�u<�8u�ٗ���0:�!k�x$������c�9B��(湥oy�e`��E�f�l��}W���NҠx�%sKVx=�sV��T?OgW�j 1����c�%xf�������`vb��`��9��8L/@��:ڈ�s�4�ӂ7w&WiC�q:I�7crD��(����0��b�
�a6h��;d�i�C����YvYp���r� �a:s�۝2��19`�[KE�j�Z�T�C�*%�wQ�N�e�g9{�\M���70C�o����=��w�N`Z<�Χ>����_}]���m>�������9
EUZ�U��U*v&��슞?�<�C�Z);i����%�^�0t�AI�/׉�"�a��0Hp[�<4|����΃�5�ɴ�%�;�&H.;�	�-���bBQ�zlU���/����@�Z��kx�0Қ����3k&UC�Ac�J����2�y�\�Kk���� �7�m���7�z�������p���Hn�Y�������w�O�ޜ��6��?�x��W�4������u�:G��޷��S|���k=�Ma�	ֿ�m�����8��k�W)O|�-�K�u,�Rl�>N|f��s�z�t���ͽ����؍f�O`ߞ�@�S��9�1�f���d��'��U)��C׿��>l�L]h����߱�cI{Ih����a#.���� ����"��r{\���d�N��k������}��K�c�!�u�+Ht�z|�l�
F�E��#�:ЗG[�$�6�
��^0���/4o��P���e��d�����`�܏�����Mm�����8�o�I����aOb��k@�cA�Wgh��z�����a�7�-��Ɯd�� 3�1F�J� ��{�� �� �7�s��h��4��ј�@�F{�~�*J�b������";�	���#�!7h���������v��ֈ]��i��FTc��/��}�\|����d���q���lԂ���_��t2��8���P�>�!�/�
�[R�*���w�~O�)�|���s�.R��Lz��=���A�8ވ]Эxl�����kס83(��LR߳�aŞ5N�߰�㨺����G��{�Q{�>�vj^���;�)�c�������&��N��	��VYʖ:�q{']N�<;B�
��b*�!ϧ�A{2elƵړ?���ZR�K~��m	��WPagj_�|bF.�Ġ^<%�/��v[HJ�7�����0�`�#��*j�?S��2\�P)^�5�0�KʘN:�d��QƬ0��?i��dA�#A4��%�ξ��a�G�Bu��/0�����o�ĕ���/n��cGx?�s�����8#D1�{l=Y� ����H���d�`}�v���u� ��]���>�N���ğ�r�J��o�I�Թ��@E��89��-h�%H�'0	�ьJ���Y��y�'W��xm�~{�sL��Lz}a#4dA�Cm�K�W�&BO�TgK��O�ǑK���4������A�t�k�p<A���ࡩ	�;R+G���z��%I6�^>�s�l1�ɟ�Xsqמ��?����Ё�K2� ����x0��`�(A�E�p�9���x�8�y7v�Y'o��&рu��<>���DLcE�Ln?b�K�m���F�f^@2'�h([֓����\�yz�+��\���X��.~ެ�X�`��o?&�CrS��(	�S	�+'�p~�&0:w��2�l�ˤA��&�x�m#�]1�	$�X�툋�5�^�{��'��GoN��IȬV+%�2㷱�Vpm	��k�:�t�9���/ 2�]����vƸ@s&�AU��He�WW�l]úza�.^���%��Z#|����y|�O��?K'�� �  