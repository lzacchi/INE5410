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
�      �<�V�ȲyEG��dl�	�!�$�!��I�FK�m�[�Hr��1{��y:��;U}�ZrK��u��+ARwuݺ���戆�)�����,� �6����6k�S���fs��\m,?��+�����XJ�$����ΐ~r�|�Y��GS��������rs���$e��<p�����F��ݒ������i�'++O���/N���{�t�zK�N8(�;�|�{ر_�����;���z����)q=2�K���!n��yB��wR#'-�e��*Ћ<gī�]'"ƼJ°*L�;��q���n��k'�3:u� p��#ǮwF�c�> D�Q9�i8C����:)������X��n��
���h̴�Z=k��'�{��������{[���=n�����H��#\���8,�]"�g�~�T?oV�i�O��m��(.Y��y�ۗ��u|�3旎������nf���[D�f
�ҙ��f���d����o���,} ����	����')k�g�ӣ�sǍn��,�_]���f�~o�w�T���������l��o�����/�{w����J�E���|s����f	��z0��\����A�z��7Y��P �pa��@8�tL�e���
��و1 �Sp�h�hŁ�*��a��ϏtH"wD�IT!4���z>9nH&#2�']qq�-�L�$dɰ<��8���g�!h�D������~p�f�G�x�$*gh>���(��Rb�����HVG48��m����X���'OV���N�j�����m{�m�E ����F��"��g�1����þv��u֏���$b���O����Gӧ�w�t?aR���WA�6t����q.mB�#��d�l�3�����9җ��� 'h��܀�R<9�Q���z1-����_��ٻ���Y ^����1~�嗹�����"4���L�O��[��uz�m��H\���<o@�I�1�o�m3��pa�4%�Bݲ$�i�~[;)��b�� 2�(�	�,���U	eY�4���(��.K�`�g�@�ݫM�ʶ߿9�I_����_�Ԅ��:�
�*7[)��4Բ�|
x9̓����A@j7��c̻�%�jqlA��Ɣ�L1��4�2�J|��rcGJ�|��K���)�IN����^�y� ��8p��O��G����Q!�ҥaq+5���hj��7b�CCD�����) b�0uɭ<eaü)� ���å��Zmi��G� )G��㔌����s"?��y��[���������:5�o6���w��ܾף}b���������?�;�������+��m����͇(͹^w8��S���lq���s�t��A�����ѩ�zn�Hw�e�F�U�軽4xJ���J?���A���s�fϟ�� �> L7b�9�!FaF!�Z�^������9	�F��Za�ϝ�;��F(���3�[�*��?63�A����� b��G@�;��xT�Qdr��w:�3��;/�HC���0v{&��B�EL׀��.e_b\�$�+�A���#Į��
1J#;�M�5S�*C�ڡ3�d��L���8�PPU�ρ�@sJ�`��݁;��e�n��BU��Se�Hh&6�;AH�kUTU��ڨ��,Z�L?��l�8Ŵ?�J7�		g�e��E�K�\�S^��o'���[�Q<�כ��O�������p�vB0�(;�C�?=���t/��3L�M<j��FN4�Լ��ɤrm�j`8�c��y�������!�N�p%�Gn�������~��F(�5�v�a��!���P���Ӂ� �!6��cuX��*�f�P@��7;{����Ԟ��vOTNj��֞�y#�(j��K5�@@�#��}��"5�AYЗ������y�H�A�<�Z�jI�xEX��Iӹ`T*Ec�}O�N_J�1F�1�o�N�:I�%6�a�N֤p��U�L����T1�I: ���KGÀ��)&G>��y��hL�I��&ƅP�L�H�e�R��D�g���y;@iw|a�
�b����CK�tf���0�\�ؗP!.ԭ.7��Dch�>D"�{�>1bU�Lc(��8Ҏ�k�j>c��P\Ѐ4WǲF�����Z?6���"�g������t-PQzF��K��(E]��k��eH�q�7�:�qtb��4T�` V��	�0�Di���~&5�&�ͥn��N�L���$�ݡR3��u!�=�RH���O�8V�=�A��D>���,�*X!f,m�Y]l�eUX� ��5R\�L
�����H���
�#|	�j��<\'?{?*�)���5�JTY�/�k��k��H,�!'��ї/�yy-]���x4���Q��VW��Cq'Dq,� `��(���N�:���u�;�g�Bb�Q�-(�
��S�$N�}�G��l����3�"ɘ1""���]�a%�{����n
�i�F�($ԐdtކA��97�Μid�I�y\E?�+�T����.��,O	�م�(�0��:��`��S���2�u�)z��s쏣Pg9z�Y�*����+=Jrf�q�e�Bf$-l�.Fg����b����������V� V��d�PX�b;����!'
� ��ޗ#���<C( ��	��G��l�XV7���Ұ|�qt�$-���u@y��J�:M�EiXC5�4�^�Q/���Q[X'*pU��q|�z��\W�i]����5�{��X��&N�v �&��ƾ��kN�ϳ�T���'J�0��y�H��P���w{��6�^Zj����v^�u{�= ��t)�7`�V;�lv�bՖ�";����i`L���x�>y2���?�]S�ۉ&!y�+�5���Y��ٿ���NY�O�F#�������z��+_Q����k�^�֛�p��O�~ Q��o�?��(��Q^i�M7�K�����"�g�8<��O�}+5���si�9�1�$��ꌿ��F�;f+�+q�Lx���.(��6��2!k��1
�ճ����*�U��w~�����������
i4��12Zl�+du��
_�ŧ�أQ{Z!+��O��h���h<[�G}eE�ZY�5 `y��rO�|�>]eĿ�����X�:�l�>c�f�R�}�L��g�;�d�O���Z%\���%z����	��P���I+u<0q��g�;���4����'&@�,, ?�x�ɑ{"�B��f
{ػ2r �c��L� �Cwl3���(bo��Y�K'�R��2;(���5N�P��/ŘY3�?eO����(SfO���<}���7-�¶�6.�����6/Ega���q�hz쎩9[W�m�;�'��u�����0�O+؊�:��C���M�u�g�E����@�*�|�	b�O�ٕ;�cU�j��I�Y���V�Ҳa�n\����4�����9P�
P0n5�������iV�@�Hb�	0��I�8o$VLMU������ �����L	�L��f�?V�0 5��n�c����?��o��u;{�3�-?y2u�sy�����$���x�0��W
�����dw�m&�b�rH�����s��6:�QP�����,ṙh���GF�������ϩ����k�8Ԛ2��_�~ ��v��O܀fr:t>ў�cX��=g���t��1ڮ��B����
SF-ps=pH�E�g9��l5����L�)�����Z���P0�!:j\���D7Bqy�Jy(d��O��te>�-��U�q'��%���"����v����t�.kM���|V'e�|A�j�}�:!�h�n��|��̪v_��1�wd���F(0�^3��^��h�c+�B6*r�̿18�\oBg���$^�iQ�9i���6�WC�^V�j=�@�p��̲ժ�X�ub�������:����G]�'��>���_}�1u�o��>���i�lӈv#��$tÈ�������+��ȁ�I�NH¯��aH��0��� s<��v�Vi��iou����������W<�;1�G��������`��:ޱ��L��x5�J�J�� �tl��uyR�#����z�e�,qCsdL{,{�f�=]~p��eדB:�����΁��I�o�%x������L��ys
ĪT�o��ϻ��˭�+`x7T�@���#������U-���a��'���ؼ����*�Np�z:fv����<B�����/�m��a�~�������)��������[��F����lw��,�d�F���=�u*���4��y�keu��w}u����E����t^�7�s��j9;mMr����I�f3!B��+}P��Oðpmn�鋒()]�Qr�7KU���ʉ2TG��L(њ��瀵G��%g�pHlYDfGh�r��:�l�p��{jG��W���NpV^��Ke\*,/a I?E��� v� r83�6�Jzba2S8�D0�{��{{���)�ӳ�����c.�C�	DP��9�3㽥��a�)�4 !���}�҈�^l�
M�wY@Q��S�k��9D�M�$,E�wD�����D���x-,�f& *(����	m��k���>��_�u��J�<M�M�z�������Z��;��f����������z?�������X�2b����w��a��`�w�gn'L�Sy:`�0���Ͻ*���#v��
��
�c��[���#مuC;��I�i���W`w��'��I�+�Z�#tbЊ�ܣ��[uÅ���o �x�z}�!i��܇��-BET�F\@�Y�_�\�"�0�\s�%�HʗS�9�a�5�3;w@���"2��P��yD��J��t��?�;ʅDN�����.MdZ�3��^���߳/;�?��>h�X>�aqv�[�,��o��E4�Ë��w�Sw�%����7�m�T �,J��=/pmJY�]@���u�0��ɳ�؄A�$V�S�=d���f~r;꠳�m�n��������7��Z�?�������F�G!;��I�����r3�7�'B�0����x��ʑ �H�0��7�q�xao����\����Ł�kK~�st�����BB��\�G\�TזOy <-"�*�;��5�8xŃ��MK�NX�O9�1��ر�Y2fa�'���L}��%�r($�3x�a���]����X���eJ� L v��ݒ�iH����b�2U[��mH�EȮ%´N�m�ۉ*�\���No�.���s���\b��;p-(ߐm��^��
n=\��e��DV�nn'���V�y����YP.b[Y��A�*�܀1�K�V�q�q���"t���8�!]�J�Ift�0�b�8�f��H�03y�2c�8�1-#�F�u�7�Rm|�![7��Ue�y�mj��Pv��b���V���`���%;��[����Oŗ�Y����2y��
QK&wH�s�Suu�n"�VM��&c��v����1)@���+�/���P�0޹J�W@��8+o���i�Ӳ�cr��*�>:Ѵ̅�8���X�i��)�U%�����G�Z�EP�*d�]�t�Ze�Oގ��wx�%t����V7ԥ�4��������H��H�����&OƹK�Q'��7
fT�5Sa5�[,L��,`1��ǖ؂���U��Ԋ�ؚ	�Ja��Z��������쑘�n�l���`��p�`�BDʙ��kF����D���!
�������v����F+�w0.j*��=<Q�C"~����O��aF읽-\K7�M��L�W� ^����l�jo�jo�;��hoTL��_�:�틣Q6s�ϲ����}t�ږ����*�__�͗�'_���h/ǳ�8"��ӱӪH�:��r�,>�V��~{��|�-0����(N��rE)��W<ĝ�t=�2���q��C�,&}2<<����=]s�6�Ϟ_)�jf<_���J���V|��#�e'u��J�=$g��$v�c򴵩ڧԽ���u7>���H�S��f�!�F��ht�@tJ�:|��=�6X���ײ�e,n��!�i�$;��>7��EP�gݜ<rv��uG4W������M��l��(�ui9{*,���8La=p킗��Rm�op���Hu��6��S؏Ah�b��sy_�Yo� \n�jȕ���̀e(0��H���$����TY�f0����c�x�������-�������w�f@j#,�J:��6u.5���GqF���i'�ǅ&�_=>��S��(�I���N٨Ū�D_��ut�]tu5�4>�.\~׃t�F�bj��lu��3�\�*b�d��ow:Z�+m,nRq��Q�T[?�=@�z�*�B�ˑ�Y�H0ٜQ�Puy��BֆL+93�*\����#��
���X�s�rDfNQ�kS�ꦤO��'z��+���Jw�!~�}�#�kD�r��@���7�4|��Z��g�l��~���A�iS�ya&c,��C��Y���e�"	K�{äҼ/0��u��(�Re_���ܧ�u���7�O�����y�D3�@�}���*"\�JX�����~*�uI���<{tjU}��,a{DY�y1`T��J{X3��؋�`�s��H$ְ��l�3!��d�Dޏճ�.��C�l�Hf�[Kg_�����)7S2����%7T���s*$��%��l5�#X�0�fG��4v(�ټ�>�H�X>����"�k¶J4���R��p��`�6P�؉���ekfuu;v�������	�P^o֨�!f�qU���˰��9���@+?/�P᳗�~�����Q�
��)�?��+h_���>�@�ƍp�@�����L�,��t�l�Y�|`L!Ig��U+��c�T57�T?�-�D��r˾\��X��i�S�qQxe�u�j�%��mcz�n�ݟ�o8w�}�<Nw�WT�R�sd&* �.�-��1+�B�>[�<W��:$�Ң���S{N�B{J98���(��V����4|�2PV���٠/'H�Gi������ϗ�s��3����G7'����HW�s��N�$8�S�w�%HX�:hF�B$o}&аԄ~|R�����9�B�m���}-j�����$�>�6C��G�B�׏��W2+3�*E�+8�qTt�q��=��b��v р��s7qK5��ʩyr�����^��B%7���Է*�>&�Z�q��o@��V��#�إ"��RaK��T 8���C-�t��پ??��b��rj��  ���7.A�B����:9�
��Ӌ�w�b�&��KqCq��JbT�����n��e�q7ޛ�]�\t�����[�{3��/}<̍/mLG&s[�x���	�	_�1��E���F)����/�5�;.��V��;��.����bnʽ�ٜY��v��Oa�c­=�	��w��a6���%2!n�+���P̙a�I/bAx	�C����E�ǒȹt"��U@�>���r�
7����9mkF #���{*<��EYMA��Y)yP[�?
�"�W=�;,�SW����L�b���, �6�sR3�e���� �I�j�]�P��F\ ��2�����B��1���7��[j��ۏ��G�(���ߚr�-s�գ|~��
��[O�|Ԋf��ӫՑ��� F�C`]��-����,�Fg���պ�{#��g�:�|�?�(p�:$�?ĳ�$�Zʒ:�>f`ֱ����N�p!���D��K�v�d*L�����5�߫� b��W���?��	��:hK̞�w������2f��L�>�[�5���0}m�X]!�Z�&���f�s�_�rF!�Ǭ�x�v]x[)p����[B�[�D&;�J>\CZւ#
���A%іD�씌ma��{c��a�VJ���>Al���P�ݗ5o�}=`�)Mڜ�\�>��1�p�l�����ǃ��l<n��`��9��FW�����W���#�[�d���	�u�|����W���Ϙ��-7์rBF���P,�dĳʷk3��ӎt�;c���|{C*H�l@�í�V���߬�������.^.�y�R�eD�
wN�l�ټ�h)��[��[��^m�/�~]�a��C�c�u�(W�>��,����~Hژ�]��,u����v \~#bz�5���]��G������O�����@B�l��T#�*]��ޚ�umj2|3��FB1�n=�����A�z�~�|��;n���4���ƞYq-�h��~��#~ ���x7o��	/�P@�+�%�Nd��:s�	����00����s��)[D�y�j)�A�p�o�+�i�̘�����o3�<.��$�4e���jq_�ܒy�4��r��*XZ���|���K�7�0Q�ںW3,憃��w]R_>�4���c�������\*����[�h�E]Պ��fm��)GU�Ⴝ�۞�U�o9Ʋbq�^�u��KE|� �|��6��f�5�gWY{%�[Ep��V���,V�6��73��mƿ�N��leX��rˬ�4*U�jު�+�]e@��L��4��5�{�C�Nr����2������jg���s<��_A�=y��E�0F	3e��;�H�^�5�{	�?�v�%��?yI̥���.ů����l�.k�/���53��F�V�HW᪉�0LO�����/՝-��-:�es/gnxz
o�@`�"M3%e���1n �����Qn�'�Sʌ!�L�f����OQR�J.2-1|fWai�5���UJ����sn|�DL+�#.�-,�Jgr,�hQ[e�&�n2����.�ճ�S����0u��?|�0��?�V���x*�d��;:��U+x�2�L��R+Q��9D(���g�%�茼�$�xc)ܦ�o�x��U�p)���Wm�iMg�\���'_���#M�0�d�O�Hq�G�n|���/�J�K�0���4�̋H�no�W�[���t\�h

���@����xd������~��Y�x�1ۢ�o��x��4�&W��^��ւ1��Dgy�>�!H{{CS���4�il�N�н� �q��g_9Tm^��Ɲ��a/:3��D1?�qP�^�z
�����#9*�}}5V⏯���Ƕ���A�\L �X	}����w�5xoG���d֐��F#��m�����:�����|$5~�b�܁gjO0�)��"�7b`aEم�jnzZ��<���ӿ����)�� ��{�J�W���>��AN��}�`u��gy�X�z��ԉ/Z2�s�a_-1���Ɵ��,q]�wX�8��Ć1�����鯣ׯ^�~5������a���X��{����:��L-jv%����?����R���U�؉�"�?=�iM�94�wI���(��㱅E��B }hMg��������-�Ϙ�e�s�	�Xv�3ƌ�L~�H�/�i,O	���n�l��>ft7��u��~�@72*R��&�����0M�n��l0o�Έ��֋����5�-�O�.�߀/l4�a�Pv�+Ӻ���q�y�F��ư�\��"5s�.x��A����O�r��}5�?�����;z������y����g�y�+�?�]�>����9��Z�f��)�[���s����s������~��y�:��ӱ]�>�k�Y�0K/fN��Ի�<����p���@�.���O#�����,���OgN�%�,D(��6'<��r���) �8q�G
� �.-Z�z�P���4rce�=yB�#����my����W�P��"��nKmh��wj��g��"P�� ���|�r2v��E�,��C�g�;�~<� M 0�d� �E�Й]:�ԝ��4	��r��������k�����p�?�����;M��l�����!�:�8#c\0��	9����;7	[�]�'� �ԉf��N���Q�F}X�2�/֜x0��b�_EN!�é��`����/��;p��ބ�9H���F�>È��˿s`-\����gG/�p�ñ��`�@�8���AGN��`nּ��A����-�!�m��)3�߷����̳��o�O��:8`Z�A���^�V&t�������G�����S�y&G�s�a�'����7(#ثNk��?����=lFo�� }v� ]c�Np���{@�4N�An*F�+@�6�����@U�_��6p�Ӄ�>���:B*�7�<���9��P:ҡ�3p�q2��"�إ��"%���._A�����3r�%z��'^Ԃ��áD~C�!�y#�S�'�I;`������2��H��P��/)c8�8��zC�Y�o2J!/Ȃ�G�h"�K����O��]m�:���WD_ ���6�~�JQ������!����Ѡ�x����=k��h����8��ɧ���d6�nopN�p^�ɔ�O���{�%���'��6v�0�^@yE�oV�:p� 4�K��`��K�+�6��j�չw>�6Aޘ�߿|���)ԙ��$�&�}���Dޏ'~:ON~���
�C��W�b`�("����Ty�d�@�?��#���oX�����0�ˡ��#���'���YwFrx����`{�u��d��?q�>�ǻ���.���&�{
�!����
�)��3ŖQ��%c�؍����z���� i8s몑��؀)6`m2�:0f޹��I�	���/X���+ؠ����p�$���î��E>�T$��A������� <�� f,�R 7��+����/�7%�*gO+/'��+��h~�&�;�҃E
�L�<²���l��q�]1��$Xǝ�"�4IfߝyD�/���>�˦(k5ZGI�Y�͌���R J��(�F���U}���#dF�G?&��,�q��L���֥�OM'��]���`�=ub~��� ��{+��Of���j��O����U���]���v�J��ܡ�O�����Yq��X��Kt�$G0���n���c�۝�[�~`Mu�x�	.�^g�C�]У�i��c����	�e0B��9�Ms��;��l��դ4��Ԗ�5h;���i��
�x�w�
���+U�g���U�߿�1�T$�o��o޽�,b�����+~��( ��d��U�5>��a*	���r�/ߍ�`��8���Vf"�9ԈNd��~�.��a�)�Ƚ6�O.�D�,/��c@_���ѥ%k)v[��$���ѭ:�~�Z�>m��(6jV�Ƒ~���D7�����u�:s�I�B��F����-�v��=�sr����?UI�1�o>���WC�0��=�l�J�R�t�'g\����}�Ez��E*�&����^bL�
T	0���Bn}s�0U��댵JWz������ҲdY)��`��ޯ	��P��x�V��4�-���&@'А��
� ����P������0I'����6��;�|�V|�t�p�����A�RJ=�����s�*-E�����v*��T�DE��tƮ,�$1:����`)�*�����"�	+?O
2jm��J����;��cq�?A0;3��jS�τ9��N����	y])�m��m��Mﻕ�5�7hP͗:�\�!�K��o�#7m��_~9��|�;Z��|���Z㹼�\��X��qVlYV@a�nX�68�+@�Ҙ���r�wvO�X��<p���:6��D�������/U<�*���B��v�	ښ��)X�Q���jPgĕ;Ug�"8��;�Ƃ-�����s'�(T��H>���Մb�h�������ޏ�+��£�'ӛ�wH왵E�X(Y)P ���I�1KPdq�RWd�t��,�ߠV���rX���¥\,,;uϽ�a�B�b�=�|XF0��;;���9"���p����h\ MY��F����JF���cL���GtB亴4��0m�n��ch+�Ӯ��	#����P�Sy!�����x
�K���e)�&�oqmη�tZ.X(DѓV�n���rEGP�K�����h +rj�̓�<��r�1ӕ�T��lb)dIO�_�a�k��i�a,3[Ո��Џ,oM����ç<�J�*U�1�@�n]-�2���/�(v)թ�~	*��	�����������/P3�����n�Ŀ��(��1ͥ��2�ڴ�l��sN�F&T��` �y+��)�60��R�=�K��&�E����P�����<�pb�n�b���y_��'g�E3C�2�� ���k~/C�a��q3Z�s�#�L�6hL�U�i��Go{���i*[J)��j)ql�\f���.�P7rћ���Y�gG2���m{WJ�,�u�Z�*~eVl2/aĝ�@N\��U��w����x>]��},�k:�on��q
wa��.�0�a�߭̊�����O/�+���an�.��+=���A�?EwNdK���Qr,�����)�h�H��I������EQj�����V��6W��Y=�g���ճzV��Y=�g���ճzV��Y=�g���ճzV��Y=�g�����o��?zDZT  