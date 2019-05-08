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
�      �<�V�Ȳ�:���p2���6<0C�IXC �������X;�����c����t>!?v��"����u��+ARwuݺ���戆�)�����Y�CZ]Y�gcu��>e������\]����7�����ʷc)I�0rB~p������*�?����#��ߤ\���V����NR���g\�O�n���-�;���K���Ť~;��߼��,����Jo6_�v��;���r��|�ళ�(�����!%�Gʿ�H�/���)3R��:9i�h@=(#�U�^�9#^��:1�*	��0���'���^{e�Q?!/�ѩ��S�9v�3R���2D�T�U���{^�0��W���[b�߻)�K*��[�1��덬�77���.�j����muv�����h�B�#��K�p����bvaX��_���S��Y��]9��U�,Q\���c����'���3f�����M��nf���ZD�f
�♁�f���d�����,} ����	����')k�g�ӣ�sǍn��,�_]��++ͥ{�������m4���ngmk��^g���_���������v{����o��vR�`�����O�,��Eo2� ��@�B��@8�tLʌ2|�CR�O��l��)���|�������@�G��0���:$�;��$��i�x=��7$��������т�W&�dX��t�\�q�z�3� �J"JI�QU� ߻P���#{�A�34݈4x��w	)��z����$k#���6���o.M�������'I��ҋ��������" ���w�Tb�t��P�~�a_�a��:�G��x�Ƀт���P���S�;u��0)���� :gt���K�GĂ�h8F6���lbqD��%'�7�	��07��G�hT��)�^DL�|�g�;{��z�<����p6Ư��:77Wn� BM�����Aj�5�P��޶a���
l��4�����6#9��˦)a��%�L�p���Iem��F�HM g����U�I(�R�i�xGipwY*#�8�Jo_n�T����L�bo�5RZ�#� �*��dl����PK*�)�04����=�݄[�QvK�q���*����)q�b$iZ��$��*Ǝ�p���d�S,��$s��9�A��q�zQ���c�J�K��Vj���hj��7b�CCD�����) b�0uɭ<eaC�O�]�O�O���B���x��e�����ۇ�qJ�����9��⼅����A���r���\����4���w��ܾף}b���������?�;��γ���K��m����͇(͹^w8��s���la���s�t��A�����ѩ�zn�Hw��F�U�໽4xJ���J?���A���s�fϟ�� �> L7b�9�!FaF!�Z�^������9	�F��Za�ϝ�;��F(���3�[�*��?63�A����� b��G@�;��xT�Qdr��v:�3��;/�HS���0v{&��J�EL׀��.e_b\�$���A���#Į��
1J#;�M�5S��@�ڡ3�d��D���8+PPU�ρ�@sJ�`��݁;���n��BU��S�Hh&6�;AH�kUTU��ڨ��,Z�L?��l�8Ŵ?�J7�		g�e��E���\�SY��o'���[�Q<�7VV�O������]��a�	�,��h���?tO�y4�:t��0�7�\���9� S�"\D'��5�����i籷�W;[��;�Õ��]D�*R��c�����a8��`L�݇YW�pD6�C-���N���؀���Q`A����C�_��1l�[��S{��=Q9�}�{�[{�$��q4`�.Ք�e�`�ю�ԐeA_�2������#����j�%�c�aI�&M�Q�]�)�=:}.e�X��п9;��$��؜��;Y���V�23Dl��S�0�r$��S/j6৘��r�ף1Y']g<�B-3�"!�E�I���eC$��� ���	X�D�%�r"e,ә1vV�<pYg_B��P�N�ܬ�A�����z��K��|�U�0���L�H;N�M��D0���WH@q=@�\�1�B*Chk��xⲋ�G��#?4ӵ@U���.�O?�u��z�I�+�!Eǽ�4O�\�Љ�Z�P)�XM�7$��pd���"���ɚ�6��ib<;2Ŏ���w�~H�|��D�K!�Z?��X��e�P��P̪b����gu}�m�Ue%8��Lq�3)p^�oC��"�:b*h��u$@j��`��t���اDl22ֈ�*Qe�1�H�Q���J#�HB��NG_>����t9���y���G�
Z]�J8�a�ű��5��l�K8	�t`��֑�(��*�6E�K���*��NM�8��i`�C�/��ރc�Њ$cƈ�HR�v���`@�Ų��
C�)T��͢�PCj��y����P;s���&��q�Į�P1��g��s��<%Hf�����@0#�a�O�*&�|���%��9�ϱ?�B���-g嫐/悧*��0ə�����
����ͺ��g4Bs�����;�{;[ULXI'��Ba%��|L�f���(d���z_�t�.\�� P�Ƨ�&d,Dlh�cqX��_J��;�M�u���n.0��} �u**��41�aՔ�|ziF��2&Fm~���56������s]��u�6.V�4�VbG�8%�5 X��>�N��9�3<�zS�j8k�(��x�����!cB=B�������{a��FB��y����m����Y�"ހٷX����ys�U[ڊ�H2�ut0�7�;��a���z�wMAn'���a� ��$�g�f�r*G�:e�?]K��*.�o��U�P�|E�v���z�Zo�ÑD>�D��3���o�<TNFy��7��.-2����3�ɣ��"?+��8Ԭ6s4(Υ)����� ׫3��?�!P��)n0��6n����v�/˄�)�( W�6�:׫�W17������6�ƗO����\XZ��h�٨�Յ�*|�,<y����*Y^X}����zͧ��h,/T��& ,-<]����J�OV��/-<~�=���� WV���J�R�}�L��'�;�d�O���Z%\���%z����	��P���Y+u<0q�g�;���4����g&@���?�x�ɑ{"�B�"�f
{ػ2r �c��L� �Cwl3��(bo��YkH'�R��2;(���5N*P��/ŘY3�?eO��k�(SaO0��<}�����_�my��˯غ�����,�5OM��15�c�
��s����N@�"�Tp�&�i[qRGy�O�y�ɿn�,B>�H�W( W��=A�ƉB:��a��q�jU�u�/i2Ws�@�J�CZ6Lbҍ���fS��8�R
ƭ����W3;ͪ�I,6�41�筃Ċ����r�8Q�$�@י)!�I����J�&��v,ҟ�����M6�ng�q����Ǐ��.�ޟ����;�o��J�r�S����Y�_�J��+��qT����"��!���Q'�6�#�wF�s꼇�1�0�f��(�������7��܀���g��V��G�;��8&|��kc�Pe�}��C�D|�@�Y�a#[!gp!k
�¥�j�V~�"�w���W�?�"QōP\^�R
� �#�A?^��t��t�Gu�I,~	�����*�b�]}�`i;��Z�up/��I�;_����t_�N�&��13߮#���W�yL���tG�
L��}���4Z��ʠ���\��o�#כ�Yj��9�vDZTlN�.���>�������5�)�o;�l��3ַ���)ff�;����}�Q���>���CcF��XnN��[������}�#�4���!>	�0�#x�5���㊨9r�}9����|Һ4��;��'���U�nw�[������^6���G� &���u���{�,Y[�;�:�	[��V��@���뎍?�.Oju�oD�[��]Os�,�%�bh��iO�e��L���.R��zRHG�|�!�90{�:�;⍿�Ӣۻ۠V����Z6�@�j��V�zٵ4^lm]�ۡ�:��'|�������� �j!��>�?���m���U�v�s��1�������uͿ�~~�n�o��������oO��z�p睽e�9�j�7��'����gɎ0 �6�����S��������_˫S翛�ƽ��������<hon�N��rvښ<�P=3c��!�fB�(LW��:���a�����%QR����o��t�e��Fř.P�55�k�N+K"0Ύ��ز�<4̎И�d=u�0��6s�Ԏ,��8/V�ଲ(�+�TXY� �~�(H��4�%@�p:fm�=����d.�p0�`��
�)���;b�Sn�g	I�;�\��d'*��`'r�g(�{K���TSBi@B*��#$������r�Jﲀ�F����ss�
��SIX��5�
�P��B��
O�Z,X
�L T!Pt-<!;�\�����}6C��&�Jy��T����)����%����vn��WVV���P~?��E�]x�G,C�z�~׻��0�U��;�3��ѩ�0v\S��^�^�;��Z[@��1_�-K���º���$�4���+����Gۤ�E-�:1hEa�QKĭ��B@���7�p<p������ZT������"*D#.����/U�Q�J�O�9�B$�˩�⏊��
Й�;�̂MF��y
(q�<��r%�R:�����B"'x���f�&2���xQG�`��t��؍���l�X,��8;�-q��l��7�op�"Ņ����;驻y֒Tm{����6L*T%c螆�6%�,�. �h�ˊ:x	�J��YJl� N���2b��l3?�u��ݶw7���?�ۋ��g�xN�G-��}D��	z��Ð��$׌j�GHD����!x�avN}~<��K�H o$h�����ߏ��7��Sy���I��@���5:���``�J�!��h��#.\�k�'�< ��G������a���d�&�%�'�,ŧ��v�X̿,��0���	�q�>N�B9���^��M�.k`FZ��`�2�x\& ���nI�4�\�Յ�Y1X����Dz�6$�"dג?aZ��6��DJ.n�j�7W���s�9��h.�����oȶ\N/�j���ǲXn"�d7��E���S+ݼ��
���,(��,�ɠA�Dn��l���{+���8�؃�W�]:Nh�LÐ�y%�$3:yc1S��l��M$E���^�1D�Ø��	#��:��g�6��ߐ��_��2�<�6��M(;��D��ut+M�[�S`ܒe�-����Ҍ��K�,�bg�r��~`��%��;$���)���z7�f��&NN�1AV�����Ϙ �� �
苢�+T/�w�R�Ɓ��g��mz����9-+�1&0�r���M��\X���l�;�V���^UB|����{�5�Q4 e�B�%�I��U!����M~��_BW�1��#lmC]:K�MM͑L�}������X� o�o2�d��р�D�p��~�`F�X3UVS���d��\���~l�-H�p �HYM�x������������{����i�>+V
-&�G	�DA��	l�bT�n��O��(���`_��Ihl���:i���~㢦BK��C�8$��ȑ߭�4|v`����µt�ۄX��t{����������o�v��s�����@ŤQ�Ū�ؾ8e3���,��P;�G�my>a��J����|{�寞��r<�^�#R�>_9;�����
+��⓱iE���7���v�k�����W����C�)L��*����9��b�'��3��h�1��V����m����g�+�0�h $%Ѯ")�(��eꈒ])��Z�.ɵ�Xd/�#���T\u�\������3�;3;{I�[�L�Υ���������;�k�(���},���#Hx�꥖�L~����薛�?]}��١��l�p�O��ӳ�#�0�l��(����=U�Ij����=p킗��Rm�op���!9��Mm�MN�����U�"��}�g��R��|� W���(�X�sa�V:��w�$�X�`ك�*��&��6�����������޼:=�����
�늁'�M� &?����gqF���y��3?IJ]��>8��c�)�U-EO�*�%yM	�Z	�[w1������a�~����w=Hwlt+�.��L7�sd�|�9�i�����������u��ڤچ� x4�Ne+Ľ8�����i�4U�g�+em(�2�3��UAl��yD�����,ҹy��mNY�k]��K�Z�O�rwPNOQ���!~�}�jt"���L����,4��6�Vi��4[/���ݏ����(�<�1�O�1R�!��"
��e�"	K�[mK�x_`z���A�����rkԩb�>���;��{���>��͑pݩ`!�b��B��S�NQ�Ԉ.ųG�fY�ή�"v@���&Aի	�d��;��h/�L)#�X�^A��fB
M��Dޏ5��.���j�3���,�t���*9�?�1�@��U.iP�r7TH�7K���*^G��a&;ȳ�Y(�l޹D$i,�����Z�vM�f�f\_]j^�r�:��bͬ�n���]�����*����7kT��-�qu�U��a?�9� F����KF1���B=����
�|?�B�=G��\{��K��Sgh�hԭl��~�d./t�v�U���t�9^���9��j5��u����-�D���}�>@k�lah��d�(=�2�����R�����
[}���������&L�h+jEi��
�KfK(�Ԛ[�>��<W��jK�J�n��.�9����� �XZ)&�b<����@uX��=-��� ���f͘����Wn(��~Q��P�E�u��l��Ҙ�PW�vj$�Y���/��r�AfԢ�% ��gKM�G�[�0Iq����v�(=1�ұ���*�����ܱ��ދfj4�q3�����&�2c�Rd^���17Е�hS{,�Ŕ3,����������\?ϩyv����7���E�ܰ����*�>&�Z�v��o@��Vl�wr3�QlK%�~� p���c%�t�����O0��+�\���<0-k<q�-�j7$]r�{�/�߱�Y�x�.�e3y�Ĩ9_��~�0~�aܭm3r�}��<m�a��6cX�Tz�/��;:sh&b��`܆kʈo���2��E��q}җ�j�;.��N��:��.���d%n2^�l.v�Ӌ^���0�1�־�tp��iy�M���&��m4���Q�L1�E�8�R�;��4vNP�F ���݁�p1��i�@�m����!���Ж-5RH�R�,���~jE1�f.'v�X��0�c�;�,��EoE@�]&@)椁�U������I��]�P��(.��2i�R5Q�������p���,ڻ;}�?�G�m0��V��b�k���iZ+Hbl}<�Q+�T�gШ#釋3XA�uW��6�g��0*��׭���k	|>��q�^4s���7��C��C<N�R�T��hVc�ک�ІR9���<�ϥ�@�pX1�$Si�HF�S��_'�l�����$��� Ԧ-1{:�i�6�*�W�蕮���Do*�8�C��mb�X�J@����a����Qq�&�W�g��c؊����}s'��%L������rg-8���V9�"ڲ�Ț�
ږ��7vW˴b��y��b��W�"���y���Ne�f�s��l܊F��}�rE+�5Ӄ�؎�umA/�ec�r+"`?*����72"
�WPKvа .���篏^<?<y�:�*�g̶�)[��2j�	�Z�Ce�p���Lk=���R�����z����7�AR��v��nAP��]	jk?��h��B�������;h��?%#����2~+���|Q�jM���M��ڎ��^bk�+E���f��ϿlᇤД�2�ѳҕ��{j�͙��k�=�r-�Z��������}A !{��hj�q�.}�o]����2x�=NC�(b4k=��ݚ�f��8�����hp�:�:Li�]!�5�Yy-x�	��q���~ ����x7o�ԉx( �ޒ�$�Hl]8Ӕ���C�������Üj~��qt��5��Y�â�BW��n��W�b��W/���Ks�d�⡌�V{-�qɭ��mS\,7�ռ-%O��~���K�7� �y���@j�D1�P�K��G���Ux��fv_�0ޛK���+-L�u�h6kmN9�z��]��\���1��;��i�m\*����͖w�W��7�Ϯ��*�[���R�b�Y��lؔ�4f���m��~*wɖ��ݥ�H�ά܈�Q�U��ux�����y����(m�[�9��%�x��/;���|����)��/Ǡ���8xY}�VBO�>�kҸWe��^����}�����]Pse8to����y_�@�b���/����3��Z�V��V^��&Z�0=�}��E��٢��b�[l$��OO@�M�A��H�LI���,��l�#�Ѹ�n�܍��=����bk��D}B��S��҆�LK�>TX�����Z���p_�9׾`"&9+�vK�ҙ�֖�Z�V�Y�˪�L�9����d�,�ԯ��sL���{����o��j��O�,�rǗ��j/Xƕ	��T��x�C��Z[|��E���8��J�K����Y�a�W	��Br�^A3Ӻ,��F�x>N�v��'�ơ]� ��Hq��<
]�V�-�ʿ�*a�N�aP��	h��/�ۄ�R��{�qݢ)0�]n�6*t��^�G��@��gZgu��d��h�~�kէ���5����e��ٗ%��cW���@�@��5E������:u���F?�ZR�x��O�44�Q��z�-	�I�8(g/M�cvX���DRŴ��<l=d�l���YX��@��$8�|K�kZ����'	/�rR�,e���q�(��l�T�(J}�9����ukxf�#C�-3{+�(��ɻs�Kj�����9�[/�-�B�{������A��o����˕��)�g_|}:�w���%��φ��~�����y��$�c�h����o^O�1d���O�q���󯎾y~:��'{�$�-�9x�S�P��x�l;tG����	��͂E����<[V(
%4b��c?<��a��G�d�fa�9�F^���RKlğ�Щ��̓�#�h)k��� �	,�� W3?6e�~��@Ƕ#����y����/�䐣B:���}l������^�h��4���0S���x��U������Q�x�� Lh`4���9`/N�o��\�:Y�f�߆��̏��$y)���5��#�xq�����γ`�mol�^{�d�3�f�c�"�43��N�q���O��?�t���	r��c[#P|��~<�2e@���F�����;����5��,�~!g>(h��O؅��B9و��⥘W�G��?��G���W����������?���>d�Iv������`�b� zGn����2��m�O��'�;���>R �
P%��0H ��N}����@��2�."w (��LR?p�a�Ƒd?��(�Q�;���u�͟������;w �	*�~<s��-K����Ř��D���^r�Ck�[�*��F8���U�Ӂ=�����,�N�B*�1�<����L�t�@�#g:����<�/B�C*~�/R��}Aw�
*̝K�O�؇��{�P��A���#)��Pj&B�X�,D>ƉTԎ��d�-$e�̡*R�@k(a���1#�t��^���Yal�J!/ȂG�h!�O���O�ȝ��:���_����~�KQ��7��#|%���8#D1���m�_��;���;�&`�$�&��.p ��>���0"���@;k�/T�S�M*}e��*�xdί#g��y	�b&�0^0���K��qDQg��u� �M��^��i
u��!��	�]����7���`M��ܹΖ-�4^��܁%e�ft���1��=;��)��(��@�)�y��W༺ ����t��}�Y���^E��̙��?F��ط�˗d`$@��o���؎�=������~�����/�<L����Gݼ�oo> �F��z�>�\��Ɗ���|�z^�c=¹�΃ɜ�CC���!pM,䊆�ӛ_�M� .�Y�Xg���p��X�`�o>��KrSΏ�)	̩ؕ��8�M:��_�!!�r�FP��I���1R��p@B/��ډ���]��}/ ��~����ɛ��b�N���D������G\[a�'Z�2��қ_B�����t��(�
�3E�zU�@*�������깓�{]�%��Zq��<%��?J��Կxp����^��ow����x�ї��ߧx>[����#��2��C�Z�(��sX��z�φ�9�G��	/�p�����]Ķ��\+ĺ�yF�����ޡnw�$�-�~g�[vJ����K�n:Xs�V
�[��@�o���ZR�݋aY�eI�*��Np��YO�k�c9��3��:�@R����%q��'������~�;F�3e;�����!��"�}��$��l��vF����=�)�6;/�'�X��!:1���vF����L'��!�z�1��7�~���DQ�t����v���c;�-����G���ޣ/J�_;{+��)��W�(n{ڛsRU����v�!j��C��.�ѹ3K�r������lw�3Ǔ���?֢j
�����h���ܕ'�:?*�����
������/1n��p韝�
�zE�?�i]~��nJQcy�-��CY����f����&&S�W:��X3���� ���k`��G��[8l�+��I/��a9�K݄����%�\Wp�Ԭ
��*���hJ���YZ���;謭��#.�1P�w��(��X�!4Ǣ�\n$������I;��~[Cn�E��I�m�iԞ �H�m�,�̠E'������X�@�`z)C��@ޙ]a�	��ASq|���:��ħr=�W�-'�3T��yy��YD�iMߊ|����g���ճzV��Y=�g���ճz�#���� �  