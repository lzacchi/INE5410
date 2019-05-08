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
�      �<�V�Ȳ�:��� ���	�!�$�q ���FK�m�[�Hr��1{��y:��;U}�Zr�B�:k� ���n�U]}sD��z����,U �5���5*�S������F��Z�j��V��4�KI����3��0n^�������0�&����_o����NR���g\�O�n���-�;��W��L�?^�7~ ��!?;�����ʩ뭜:���`�u��c?�m�6������j����)q=��k���!n��EB��OR!'M�e��*Ћ<gī�]'"ƢJ°*L�;��q���j�V+'�3:u� p��#ǮwFc�> D�Q9�i8C����:)���U��X��n��f��-јk��j��k�k��I���o��;��{����
!�r�%F����qX4�0,D�/���)�*�nO��m-~�(.Y��y��瓢u|�3W�����5��nf���M"�3��`��@�n�<��u���$K�#�ijf��i�I���Y��h��q�ۣ1���ֲ�_�Q����]$��_����ڝ-����7{���:���{/6W�[��g[ۿm,6
�}Hك�V�䯿H�ңV��pȂ��!���� �!�c��(��8$e�~�f��kx�Gk�?�@+DxT���/�C�#�O��������qC2��?�����-hye�'!K��L�ȕ��w8�@�$���U��5�O9�G�$Q9C�эH�G9}��˨�nOo�@�<��n��ͱ��g��������IR����`k�e��@�2�]+X�_�0�3���w�Wnb����~4�Dl�`4��)8T��h���N���Y�n��U��	�3�N+�K�GĂ�h8F6���lbqD��%'�7�	��07��G�hT��)�^DL�|�g��{v{c�<���[p6Ư������X]7@��|�)�I��{��9�N�m���ؘ�h4	<f�F"r�!.-���]�Z�$2����'��y�@%#5�GTb�bV�,�,K���ģ8J����B!!Ǚ>Px�r���w�`�;xc�W#5�E8��°�5�V
�6UW�O�S��<�
�d	��vn=ƢkXr���V��lnN��#�H�*��'�.W1v���G��$�؝b��$���U�9�gB>�׋���x�\�%�(]�Rc�0M���x�!�>41D��O����"��� S���S�1,��� �k���)\9^�TVV�~���r���?N�����='�r��<�8�?^]��k�����Z���"-�}�G�Ķ�{������?�;��γ���K��m���͇(,�^w8��s���ly���aЍ9A���ڮ�F|E�tNP$q׳����K���4�/Lm�t�)|��0:kk0/k���)����4p#�C�g�n�E�eA=
�O����ԣ��F��܉�;c��M��=���%�r��c3�N!�QD�A7?4��yfw�}��!��z�����=�}�Gj�f�共�3� �%�/bn���p�v)���&\�� E�E4� v��� ��Q��)n���RT����xH%+�'���Y����\��S����!��,�w���b�`�*Z��fbC���4�VEU%����)ͣO���f�3��GP�F#�!�l�,ֿ�׃(a���_�+���7K����И=�Wku���z?��EJݮ���,5J��0�l^o螦�hxt�c�a:o�P;�7r�A��E��~'�kh#V��$�do�v���J�+�?r��8U� Ǯ7���7�p@1��0�އYW�pD6�H-���n��F݀��ԁaY*���C�_��1l[���S{��=Q9�}�>̭���F�Q�80c�j�Q���G0��hG�Ԑeq`�2�޴�y�H�A�<���jI�x��$Õ�s�@U�.�����>��. c�ߜ�Du�BSlNÐ��I�rS�p�#"�?SߩbY9�t�쏩��5�RL�|��9��јl��3M���R���"K�
��Dϲ!8��v������%��C9�2V���;+a���/�B\�� \nV��� �R}Nd=��%}b>��B��P��q�'ק�|"���+$���i��e�yQ�!��ql<q�E�#�@aŇ���Z���De���P��Lk=�$�ː��^o�'t��
��p�i��� ����a8���Ή�	f��TȺ�6���c<a2Ŏ���w�~H�|��D�K!�Z?��ȱ��!�&�/&��U�
1c	h-���`�,��JpL���'W� ߆E�u�T���H���'������I�O��dd�wU��Ru��X�t?XC�Fb��9!���|���+�r�7 ��4��huE*�8�qB�B> ֈ��/��$�ӁɛZG��|J$FX5/ق���k;5I�$ߧ�Qq4� �6z�=C+��#""I��ujV��ˊ�+�P��j4�DB�AF�m4��sC�̙F����U�3��I�p�_(��R�qΊ� �]��B��3Y��i>5+�,�!~Z����x>��(
Ep����Ű�\x1<�x��I�<>���6�I۬�љ}F#�1��p�jo�����]"���t2,̬d���I@׍���L�[X̑��υK�# 
��TЄ���MB6a,˛�K@iX>u��	�A�l�Ch�P^��R+OcQ�PM)ͧ�f�K*cbԖ6�
\Vas���19��iZ�j�beM��`qVp��S�]��I飱� ��=��7�,������,��(i^�R0&�#�����˭���i$���縒��}OH !�E���}��;[�7�X���Ȏ$��jXG�>p3��ÁO�L���Op��v�IH�f������,C��_N�^����k	�Zŝ���l��~�����N��T��֛�p��O�~ Q��o�?��(��Q^a�M7�K�����"�g�(<��ϊ}+5���si�9�1�$��ꌿ�/�F�;�+�+q�Lx���.(�]6��2!k��1
�ճ͊��*[X��7�������z��r�Dj��z#��Z�D֖�k��X~�=j�'%�������F�����5|TWW���J ��O�|<i���d�=}�����U�X{��ڥfG	���O8w�ɔ��Y��"J���e+L�*1B'�� �r�(���V�x,`�8��% v���i.˃��L�&YZ~��#�DP������we� 
������ ��$�f�?Q��
�\�ND�evPd]k��.�_�1�f ʞP(�Q �Ȟ`)Vy�����1�b'�F{�_��y��L��Y5>��$��cj���|k���I7p��`Ep��F!L��
�⤎4�П��t���Y�|l�4x�.P@��-�{�X��tv%�N��Xժ�+�_�d��(���j��l�Ĥ��=6��*'0qԥ�[o!�?.e6�U!P#�XlLib�=�[�SQ��z�.H.�*.�3SB&�>�����<@M���X�?�O���lx����_�Ǐ���ߟ����;�o��Jr�S����Y�_I�Z�v�l�s%��l��"�|����xd�	�M?�H��Q��:��k��C�Y"#
�����l����h&7�C�#�Y:v�;���s�Nn:N�	¡��+��n�0e��7���+P�~�c��VC�9\�Ě¾p)���_k
�;DG��֟B���F(.�^)�l�٠��G�Er��#�:�$��TP@Dw�Ԯ>`����e��:����삝/��Ae��S'd�ڝ��oבY���W�yL���tG�
L��}���4Z��̠���\��o�#כ�yj��9�vDZTlN�.���>�����\�5�)�o;�l��3ַ���)ff�;���}R���>���CcN�W]�L���}�wi��Јv#��$tÈ�������+��ȁ�I�NH�/��Ð֥a��?�x>y�t��N����v�����Es���x�Ob���[���硽�I����c;��!����rh�
������!�V�FTs�,�%�_hN�i}eϯ�䵧�.R��FRHG�|�!�i/{�:�;⍿������$�����[Z4�@�R��<�Ƣki��޾��C�hb?"N��j��뽧��B��hp��˛WiN���箧c�������u-��z~�a�o[���׭��oO��z�p���m�9�nm�*�'�����dG�}E��&�]�,�K������Z��W���$����;/Z[;������&8T����wH��!
�ŕ>���aX��0��EI��.��(9⛥*}Ōʉ2T���L(њ��瀵G��%g��NlYDfGh�b��:�l�p��{jG��W�W�NpV\��+E\*,�` I?F��� v� r83�6�Jzba2S8�D0�{3�)W��kc��n�g	I�;`��d'*��`'r�g(K���TSBi@B*��#$������r�Jﲀ�F�����
��SAX��5�
�P��B��f�6�X���h�H��ZxBv8&��fM��NIv��)�����5Ӭ��vn��0�����j�~�w'Iw�)�e���]�f��tW��/��k�s��ѩ�׳apMq�{UL{]G���i�p�*���nY��d��v'A�~�I._���'�8�&ݯ(jj�ЉA+
s�Z"n��d�?}	����xI�E�>Nvi*�B4��O��R����L�.(DR���S�QvZ#��g�:�hx�9H�%�M��;ʅDN��ͮ(d���x�F�k��tZ��ݔ]�I���,�Nw-�Զ��3[�����Fqax12��d��5%U��z��݂�Ae1P2��ix��H��r��&�V�����Ϡ�����B{q�WO=���7d���=��N{�no�����ۋ���-<Q����>�?��=���aȎar��F��#$�ܡ���<��0;�>?��㥲y�	&uEF=��#/���T�K�G�8P|m)�/�N�!;�ףR(Cc0���0
�����	��I�""~�3����x����Ĳ��� K�)�&f�3%Kf�|���Dz~𨏓��P�y�<V�ח������+s�X�L)�	��ް�:)�fu�xVV�j+>;>C�,dג?aZ��6��͔\���ND�.���s���\b��;p-(ߐm�
>��͸�p�>��rY%���,
�H��Z��M$�R�gAy�ʢ�TI侉�vF��%�f�C�=(x�8$Aބΐ�ca�5�$�dF'c,f��m���3��+3��s�2�A�7a_��x�+��7��u��^U���ܦָ	e#�(Vྎn��vf�dGY�K�t~4���2�ة�\&�X!j�$�	p�pʡ���M�ٜE��c�+�� ]���P�*�o3\�Wq6s�L�C��eE7<�f�L.�u�k>�iז��;�ݧ��ߌWB�K7��;���|�?�<1��lU��6d�-	>y;v���7��oLKK[�Tק�xS�j$3g�#�&y8��r���<�n4`,��=�k��S)�L��T��0Yt����g�_4bkI��E)Z���*��9�� ��W�w�{��Չ1M��b�J��q@�u&�B�(���w�W�
�����C�$"�:fx;��N�,������Д��D9s��5r�wk@?���w��q���6!V�2�^5�x��2F��������:�����#P1�F�8�/�F�1�|<Ϧ:�����R�O���*��_+�|��磽ϳ�����W��N�"��������iZ����ֳvK`b�51;%zz����_�t
���ʼ+�+��z1������` 0�e�:���%>6h�����&M[�0�&�i�)L�N~L�nj�4*}2����=�r�8���W���#zt��ɤJ����N֧�8'vvj+Ϊ(��9E����83O[;U�i�|��t7  ��eO��*E�F�4�9:�~3A-��ɰ98�Ѐ�c+���ky<��;rA��n� .]�<�Z�M�<�����FܟdT)m+[��|�/��֜.5�
rE�xPE�g�<��
[����x�oi��R8X֠ţ�T��c ��������*^1k~����ۣ����^����R��H`�&��$GJco2�Q^��e0�E�č�L�Gǻ/�%�RNU'KZ�U�kQRR���2�[4e5������&.�PA@�!/U�4]]`�8�� k��Ƕ�%`�e)/�c�-G� M�I������u�B(Ľ9�����i�4Q���˄FH�2��K�=�����y�sa�Y����9��9�9_�s�n��S*�Vn��1 �ܖ����_TD�J�-ߔi�~�*��0��Ex:�V���u�c>�2-r�B��#�sHp9��}Y�H��Q�R)&C!w��(�\E^UI�E��ju�����������G��ޖ�Uc����P���h����H.�|F�fV����M���&Aѫ���òl�}/:���)�!�X�^!s�΄�������+�T*�����$Kfi	[Ig_�PI�|�ʔ�dBW9�B����!�TH,�d��ڇ�*-�R�P�!�=�����>4��UK�Om��ɸ���*�9zu�K(�؉��إkfy�|��ݢ�9~�b�.���*�
���Z.��i�_b�fL�~�d���NA�����
�ŗd��4Ȯ�f��)�ϧ6�`����a�~�qpWV�A�gX�*[�$#�ZP�/�4�_�<"��)�7���ҩ��z��*�@&iK5[w�F
i���-���v�:�ҵ�&N��TzST�et_{���YH�Y�RnZ+�	XV�@��BJ�1�4��q�F��wJ!G)���Q!.�ib.�#�Y��{�(�����H�{i���i���Y����)�X�i{�
�i�:�']2[�"]��U�+c;�~�|�� a�p�3j�	����@#�$��V�6�hgw��= /��톎f���C7E�T��麐'm��3hJ�J��9�/�+��G�؍�B�J�-�t�x�_ܫ)�$�]�&Nհ�}���9�߀�b��n$ګuʢ�D2��Be6��J<�b�u����)�8x��U��6B<�����6��M2M�RN/���Y�؆��Y�n�P,9n�e����.��U
�	�S����* ��T������F���94�&F�ߪ�5Y�Ws�$q�i�l\�8�V�sqA���<݈sTSi��\�kk,�M�K���u|ڪ�u�>c�+L@筨T�g��V�Hd:�E=!��� �=���^�&�H��r/t=�������J�m`*��I��;�联l��c�K\k�OK
�����
;�Ҩ~�uڮj.'v�X���-c��5���im��M@�ˡ����3qAJ�,+T�vu�s��q��ˤ�S�әz�T},hq���36Wx7�_ݧ�b����݊p�.s��#3vImI���C$���*�+e$�Ll#�!����6q `�z�����J�j�m���Κ�-�I(p�o:۫>{ʡ�!Zʜ*�~I�j��#v��uTN�`*Ϭ�YB��)�3Sf�H�@��S*�/��h�_�]�h>���Y�Ԡ�����N3!�nD/�%�S4S�5势t|�&�U�� �R�*Ը:K��*|���4nFX���gS��R�K�����A�%ҹ3���^rg-8"��V9�����ȒVA�f֋|#���K)�����z�/p~��|Y��W]�����M�n!��וGX���?�����Ε5�K�l�Y��q��[��"�֍HB�ĒT,������������w�	U�-��QX�	�sS�R��d�B��:=��q_뮬������ث�/v^/�Ki�uh��o�U
ߴCMe�]�<��/d��x�\j�I�j�kLo���cR�QcM��B��ҷP�[�����,_�l��x�3��IΙD}~�U����j�(}Jq�����F��,i�p�"�b	�GR�L�V��|U�-9�ϧ_HȚs�I`+���V@N�}0Jcq2���E7Lb�q��i�տP5�UTt�Q�8JT�Vv��E�

�qȎ�ꞛ�N��أ�!�@���X�˪Ʌ&�S{��?
�.C�-��0ޖ;c�08�\� "E}w$��w�en&��� �sq��s���;��l�f!���֚����(��yƒ�����E�'��0�ǅ����St*��E=fY-�&��:��tt~7=|)�?�#�����u����맽ź��(���+t,_��
T Yp�"B)^�A�W�z��5w�Y�y;D��­T(m� )߳@ti�T�+�r��D�K3~)��G&^�;I��������������~����})���� 3^��)�Dˡ��{Ò0�E����������s��/ȹ��S��N�U��R�w5�Ze��D~1����dͱ(�e=��%K�b�]>�֡�L��Ѕt��u6�"q��'$X�~B�&�4�u�y�4��J#�V��"�����"]cS��6Dy"�ʓ��҄�x9�ezSA�j��k+�\�3�-=[��1�rpHXY�q��ȩVZb����-�+��Veѭ�^ޛ��4���������Ge������.R��r�g׾j#�G���;^�L�->c�4֧��;;��}�B}�u�(^%�����
��tWdv&�夝|��;;�ġ��O�s���AZ���-��/(J�����#��Ej)�:۶�૔-�l#�c�l��.�V�
�'�W��n�{���s�^W'�e�%Z���Ѕת�"/�Krz�峦+�N.sX�SW��� � ��%E>f�������	���m�K����]n+�itP[aYz�'����8P�^z	.������+�@�W��xX��l�-3��t<�@�z�&'����uQ��7W�'�.�r;���Qh���ř"=ˣ�
B���=��{�������!�f���]T�$�T�3j��F��1�G/�5R*��ΰ;����Q!��G���o!�R���DV����&�t�glt��t&s��/�BSf��v�E��,�Ǐ����1�=x��w��Z��IohG�����yБ�����+v�/�Ů�:6KGf��!1
:>��0=�;~��x[�; �����l<Ʋ��س�w��e��lP��ʌ\��3�߲R*4���������vÙ�WP-�P�ֻ�ۅ��=6�!K�T0�64�~�uO������Y��l�3v�	ے��0���H�7Ҏ�H���3�o5�ı�Ʃ��� ��R�ȾJJ"JǞ���i�ۓd�׸ROaRF�|7��%a.����xϚ�[���XM�q?���!i�>��ɓ����5��a0H^%)���؉|��7�Y'Tt0���D���ăui�� �m�2��2�� �,�$�rƗ�"�%��O�	� N��P�	�y)�U�P@�y	YO �@��w�o��� Z���K�1���7�KN�"�� ⼺�lj�,s��䡑���	�]fX��5v�2Y�� D�*+,��V��3�h�x�J�J2'�,Y���|����@2PK} 2���k�Hj���C�9y�9gq�'M}�7v�:.�S{|�5*�w��A��m�|�4G������K���+���}���o,���$��~ߎϯuIw���+����|{I�rs�l2�p���Ϝ6�jK��0UdT6�-����"N�=�/��(�ox�b�QAB�	gJ�������f�__4h����G�pv������E�m�m��|��RG��Eê�"�%V��~nb%'�-�pA�jv����NOǳ��B�j]�ږk��,8co��������#-�|�:� o���6�i�u�W���k5G��E�v:��� \@�mgI|�4� ��Ҍ@�IG���+�}� +^W]`�n"�Uw!/l�f�`q�w� @LF��΢� ��i��]� ����,PM��B K�oP�����@���}zc�ŵ��&�G�O�!S�'Z�2>1����G�+l�����ȩ �W���3d�(���L���x>tTEk>>���q�z������O��9���{��zNc�?G�x�l�(� 9(�a���BX����Y��uzn#ąa�#��{��L!�)k����k��ټUs�Й���6e
���h�"x�Ѭ���C��E4���7���k y{GH�%�L�Zh�<5�-VSՃH9�\�8=Hi���,��l>m}/ɗ���d��,'{��i������x)����>[=���Jo���Ӈ��9�'����u��y_@J�?��x�B�������.s���p����T麑�	��{t2��=mN�6k���T��f���΀��͒�|����X�ԛE��h�!�D��n����d}�d�v�� ō��<P��я~�ȝ�m)��}���X�b��em�IZ��B�%�9�(�s#Ǟ eV�&F��G{��cҠd�c����m����hU��3����(�m�}�����IW-~m�t��ۑ�]��X�i\!)��U8ZR��` -�M���r0x��]��몙H�%�/$���ڹiEW�sᎥX� Y�!u8���ү�t^�S����7�'�d�3	.��C�e������Zb�uT���=����=\���Iz����pg�3�9�hx��k�oY��1��h���j��P*g����x�?���h���ʫa��}�x�����/�
�>k��??x����.���f�G�Dnx��d���S�����"�}�yAĺ�kS�r�B@��]�����ۉ�4��k��F6,-�(@(������{���H �N��a(J{�u�ډ̎f��Եa�u#y_<{F�#� ��~�%��]��J(���B��rZPZ7��~a�)2��%�`-��� ކ���r[��<���^�����9�	 �7���x{��8�c��#(7q~ꜹ��1W���W�h��y�j����a��ƣ�����wH.��t���J횉���3�z��S7�߽}�}�� ��7b�]�~��n����S�����cX�#"$�9Ր4Tf~�
��pY���?�M�6����>��l��8�0b�/�����G�����ÿ��Q2��h6�b�
X�:V��/�
�7���f����g����T{�1hI#mK��N�o�p�uo�x����� ��~�&0d�:v8���xC�ѷ���}`$�eb׉���_�`9���g��M}B;��q�& kb�&���V����6�B���	8p;h�����8���M����{��)����4A�baGL���7��������G�*`D	vm��d�´��f�St:=�s�,Bƀ�N��=3�Y��SF��`��P���|?nw�����%��ʪ��e�q<��o��@>�w���@E����h ӝ�S�=��ߋ"�;֖���TKA�|�}�
�ى�4��4����K4�~3���}�����c5j-TY|��:�a�p��;j���E��_qZ�)Ơ ِ]����:S�C����[�Ol'�h����b�o��<� ����	C���.������#�ؤ���"�Jx��|v����W�Ѕ�GMN��0��q���G���p��{Kf>N�0�*i��g4��r�G*"�A��f4Y��:�ِ�U+JfUh��'Z.���aŜ�F���|1~5�9�W�!������Mb�Ǯ\�a�����	�� J��d2fD(&�p~e��/:�S4ց-����	�9�� �;d,�q���{��E�2�>��Z�`����"�0��)�v�>����{0:�3r���l44�H��;s�j�1Ni��q���!�Rk���+�ݠ"g�s%�@B����?��Л�؊4��{��	���J]��(���F�3��a����f�jσ���k�9|�|�09�d��9`�j}��]�r/<��\(U%����f��T��|LÔw���!%��9�wGQ �������Sf#��jх�l&�p�&7�2�P�����7� dJ;���}D8O�0F
��n�(b�*�$�����x	)Sd�z���2-�2-�2-�2-�2-�2-�2-�2-�2-�2-�2-�2-�2-�2-�x�?5��  