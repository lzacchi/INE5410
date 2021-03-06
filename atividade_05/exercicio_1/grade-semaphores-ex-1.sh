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
�      �<�V�ȲyEG��dl��-�3��5r�9�`����ڱ%�$����~���	��S��%�d ����^	�����]��7G4�N���/<�f�iuy�������A}qiyeee�Q�?��K��d�۱��q9!����p���CS�����������}��Iʶ�y�����׉\߻%q���R}1��+KK�H�v���y��<\8u��S'��l��=l��wv[������z����s�����I�~��G��,!U����&��ԃ2BX�E�3��̎cV%aX&����8��k-/�k'�3<u� p��#G�wFfc�> D�Q9�i8C����:)������X��n��
���hL��Z=k�������ER����������}��RH���r�.�~|����3{?r��6����2~[��%�KV~|l����lƌم����qö���)��&��u�B@�pf���m�<���y����$K�#�Ijf���i�I���Y�ti��q�ۣ1��WW����r�qo�w�T��������mo��o���k��.�{w����R�y���ls�����vR�`�����O�,t�o<� ��@��,�)#�p@��2��9
I>��c@�������3ЊU�����_�D���Bh8���u}2tܐ��d�;���<FZ^��IȒay*�qr%�%�m��C�*�(%UGU5|�B��S���IT��|t#R�QN�%��2j����?��ipF���cS쿱8a�++K��'I��ҋ��햽���" ���w�Tb�t��P�~�a_�a��:�G��h�Ƀф���P���Q�=u:�0)�T�� :gt���8����!��p<�l6�������KN�o�4Gan�_)���Ѩ
QSD����`�Z/v����Y�, /Rm����������l}� h�`��#uR���g�:]��up$�W`c�7��8�ŷ����q87k�v�nY��$G����צ1�[ `���pQ�	�Y����,u�V�Gq�wq��R0D�3}����&Ne[�^��/v���/FjB�pdV�a���TcjQe>����AV@w� s���p�1f]Òs\�8�
� dccB\��F�V�@%>Iw���#%\>~�%Y���$'��G@�r΁<k�y�^�#�ƣ�F�بF�Ұ���?�iz4�F������!��|��`�1�����V��0�a�O�]�Oȏ���|���p��e�����ۇ�qJ�����:�T������A~ei)w�o�N������;I3n�����������l����a�Yko��ҶK3P���C�f\�3���)��Np6��H�~:�ṕ��Y�����v=7���w�2�{��,}��n���aj��L��!��[[�9^��Oa�g ��������?ÐvB-J/�	P`|܉؜f#�t�0�G�N����?#�o���-A�[�����pIA}1E�#�?��gv<*�(2��w;m�ә�Ý{��iv\q�]�Y!�"�k�
�n��/1�i��� RT�WD��bW��p������)E��}���T��~��lp�e��*�g߅O�9!}0��N�p��2{�L\�*W���U$4ꍜ ���*�*admTLe�x&��x6k�bZ�A�}����ͲX��^��r��)/�ී���έ�(��˫�+�������p�vB0�(;�C�?9���t/��3H�=j��N��Լ�ɤrm�j`8�c��y�������!�N�p%�n������~�=�F(�5�v�a��&���P���ӆ� �!6��cu���*�f�P@���;{�����Ԟ��fOTNj��֞�y#�(j���K5�@@�C��}��"5�AYЗ���7��y�H�A�<���jI�{EX��Iӹ`T*E#�}O�N�K�1F��o�N�:I�)6�a�N֤p��Y�L����T1�I: �G�KGÀ��)&�>��y��pD�I� �&ƅP�L�H�e�9R��D�g���y;@igta�
�b����C�df���0�\�ؗP!.ԭ.7��Dch�>D"�{�1bU�L#(��8Ҏ�k�j>c��P\Ѐ4WǲF�����Z?6���"�g������t-PQzF��K��(E]��k��eH�q�7�:�qtb��$T�` V��	�0�Di���~&5�&�ͥn��N�L���$z��R3��u!�=�RH���O�8V�=�A��D>���,�*X!f,m�Yl�eUX� ��5R\�L
�����H���
�#|	�j��<\'?{?*�)���5�JT����k��k��H,�!'��ї��yy-]���x4���Q��VW��Cq'Dq,� `��(�����>:���u�;�g�Bb�Q�-(�
��S�$N�}� G��l����3�"ɘ1""���]�a%�{����n
�i�F�($ԐdtކA��97�Μid�I�y\E?�+�T����.��,O	�م�(�?3��:��`��S���2�u�)z��s쏣Pg9z�Y�*����+=Jr��q�e�Bf$-l�Fg����b�ū�������V� V��d�PX�b;〮�!'
� ��ޗ#���<E( ��	����l�XV7���Ұ|�pt�$-���u@y��J�:I�EiXC5�4�^�Q/���Q�['*pU��q|�zs��\W'i]����5�{��X��&N�v �&��ƾ��kN�ϳ�T���'J�0��y�H��P����{�/7�^Xj���ow��uk�= ��t)�7`�-V;lo��bզ�";����i`L���x��>y2���?�]S�ۉ�!y�-�5���Y�&ٿ���NY�O�F#�������z��+_Q����+�^�֛�p��OF~ Q��n�?��(��Q^i�M7�K����>�"�g�8<��O�}+5���si�9��$��ꌾ��F�;�+�+q�Lx���.(��6��2!k��1
�ճ����*�U��w~�����������
i4�12�o�+du��
_��O��G���B��W�,�c�V�G��*>�KK��|� ��Ok�x�����U�@���+OV�c�?�ry�){,7.5�Gȴ~¹L��t`�J�Q�e�.�^�W�:A��0� ِE�ܟ�R�c��p/�s�lLsY<~b4�����0�'��'�*�,pm����+#P�=���~0 9t'�6���"v��պt"*e(��"�X�u9�R��5�S���@�
� �0e�� s1����_�i�ۖ7ڸ���˫m^�.�¨�Q�$���Qs4���[[0w �O:��+�K7
a�V�'u����T�����f�"�c���{u�rUn��Ī�(��+v�ǪV�\c��&�p5G	$�T;�e�$&ݸ ��i60U;��s�.�`�jx��Q%�Ӭ
���b`J��Q�:H����-��u)@r	Tqq��2��1����a jBm�`�"������d��v����Z\Y�����z��N���W�M�w�+P��NU�;}ʶd1|9$�����}��6:GQP�����,ṙh���GF����#���ϩ��F�k�8Ԛ2��_�~ ��v:�݀fr:p>Ү�cX��=g���t��!خ��B����
SFMps=pH�E�g9��l5��L�)���������P0�!:j\���D7Bqy�Jy(d�Џ��xe>�-��U�q'��%���"����v����t�.kM���|V'e�|A�j�}�:!�h�n��|��̪v_��1�wd���F(0�^3�n��h�c3�B6*r�̿18�\oL����$^�iQ�9i���6zWC�nV�j=�@&p�mO�ժ�X߶c�&�����:����G]�'����)�_}�1q�o��>���i�lӈv"��$tÈ���:��+��Ё�q�NH�/��aH��0�� s<��r:Vi��nm�[���������W<�1�G��u����k�`��:ޱ�������x5�J�J�� ^�m��uyR�#����z�e�,qCsdL{,{�f�]]~p��eדB:�����΁��I�o�%x������L�N���YsĪT�o��Ϻ�����+`x;P�@���#������{�U-���a��'���ؼ����*�Np�z:fv����<B����[��m��a�~�������	�_�����7[��F����tw��4�d�F���=�u*���4��z�kiu��7���������n�<hmn�N��rvښ<�P]3c��!�fB�(LW��:���a�����%QR����o��t�e��Fř.P�55�k�N+K"0Ύ���ز�<4̎И�d=u�0��6s�Ԏ,��8/��଼ �ʸTX^� �~�(H��4�%@�p:fm�9����d.��?�`��
�)���;b�Sn�g	I�;�\��d'*��`'r�g �{K���TSBi@B*��#$������r�Jﲀ������33�
��SIX��5�
�P��B��
O�Z,X
�L T&Pt-<!;�\�����}6C��&�Jy��T����)���Z��;������˫�������N���S<bʈ��:�ͮ�鮂��	���0�N�}�������>�������9?�,p�*���nY��d��v�A�~�I._���Ǟ8�&ݯ(jj�ЉA+
s�Z"n�2ǟ������|���բr�4Q!q�'U~�r��T�|r�	�")_N=�T���P����el2�pȜ�S@��q��+��ɖ~O/�(9��n'�4�i�O4��:r{���z�n��@���u�d�|����x��Y>�%�� ��!�h�C3蠟��YSR���ׯw[0�@PY���{^�ڔ$2߽�<��/+��%`�3(1�g)�	�8I����{Ȉ�����v�A{w����������6��Z�?�������F�G!;��I�����r3�;�'B�0����x��ʑ �H�0��7�q�xaw����\����Ł�kK~�kx����.�BB��\�G\�TזOy <M"�*�;��5�8xŃ��MK�NX�O9�1��ر�Y2fa�'���L=��%�r($�3x�a���]����X���eJ� L v��ݒ�iH����b�2U[��mH�EȮ%´N�m�ۉ*�\���No�.���s���\b��;p-(ߐm��^��
n=\��e��DV�nn'��)�V�y����YP.b[Y��A�*�܀1�K�V�q�Q���"t��8�!]�J�Ift�0�b�8�f��H�0Sy�2c�8�1-#�F�u�7�Rm|�![7��Ue�y�mj��Pv��b���V���`���%;��[����Oŗ�Y����2y��
QK&wH�s�Suu�n"�fM��&c��v����1)@����EYW�^�\����+ �*�
�����WsZVtcL.`�U�^�G�#�􏹰��+v"�x9%����:}�y��Rkè�V�,�K"�nU�L��۱�����|c��C�ꆺt�ƛ��#�~���ɣ�����d��8w�>c�<�ℝ�F��J�f*��r��ɢ���,����[���@���*6�X��SQ)0^�}�~���|_�=��-}��ZL��,T��H9�zŨ0ݰ��HQ:D!���1Ó��n=�u�hea��EM����� �qHį�#�[�I�<�������k�&�	�\�������1�����_���a�`��m��I7���UǱ}q4�f���i6զv��X��|�<7V���˿�2���_]��x�� G��}�r:vR�]gV���'cӊ ��o7���&�\�)��C�(e����S���U�]�]9��u��ŤO��g������t�q�H>{~�H�y�$�ɝ��W+)Y]ɖβ��J��(���	9�$����ikSuO�{�W���n $ �#�NUJ��XC��ht7���@��s�`ʤ�E�\��Sx�꥖�D~����X.7e���#W�>ofS���|����҂�gKVG�����2�H
$�q�>b���^_K�����G���L�6�79%{��]��y��+?�=���[���x�G�g�2����p���Ĺ�
�=h��J�`bhS)��z���I/�=�>�{�����= ���ODkL~.5	��gqF���y��"?MK]���=��c�)�U-EO��YK�|��Q��b(����h?f?�,��]�݊���t���S����1�2́A۽�2��=�Rq��Q�T�0� �Fשl�����pa�;�����,u���V&rf^׸*��^��h�W:\��E:7��A��)� |�� T�r�S��Qn���)��=� �O��U@�N��!ߔi���v�����*�XfKe�y��X�L����3��c!�R\.�y_VI��-��}����,JU|���>ըg~�yc�RJ���\fN�a{_6G�u���p��	Y�OU;E�S#���eU_8�.��>aVj^�U�&����`F�{1luB�	�
�
��6Rh*l&�~��Uui4,TOA;�I��I��:�ܠ���SS
�	[��*�pC�D#!t�V�:ه�4{"Ϧf�0�y�v���<}�Ǎ�"�k��Uh��եV���k]n@�B'��CW����v���{
K�� +���z�F�/�b�W�^�{�c�Èɨ� Z�y�(��=�����Y���g�I����k��_|I���᠁���s�۫X�E���َ���@[B"�κ��$�\c�`�V�Y��i�^��I��.��W�$��`C#(�&�E�є	���V����.�WX����;��n�4a�G[Qc(J��HOT@�]0[B��֤�ؒ�Y��	|\e�V[�%-�i/>����.�����\�biPh%�X��H�.�aE������I�,�Ռ��]"���� ���/��c�ȣۣ.疭PWs���N�$8K�0��PX�:hC�Z��@�"�L�a�	���tkA&)�B}�E.���'�Z:TT_��2x.�>�;�C���L���<[j�^U�E�m�Rd^���cn�+ͣM���Kΰ ���'�̯��zyNͳ3̥p�^ظ�U�.��&M�T��11�:��\|z%h�b�=�̀�TD�-�L���@��o�������*�??�Tb��r�� ����č ����4�,�����s|���u���Sw!j(���8F������w����6#��:�1?�h[����·n�R�t��f"����PM��#Q\&)4*	��'}!��ָ��D9���r�.ص5V�&�%��b�=�����knm)D@�h����d�H`b:�F�+��gP��0�d��(���!���!H���g�$ %mT ����7 n ��9mf�@��`��<<��EEM�TҢ�<(����ZQ���ʉ4�)�����A&��[r�P�9i�����HTP�L
�ܮM��b3.���4b��f���j�.n1�-"��`����W��{�S>nE9(�\k���O�ZAc��i\�Z���<�FI?\�@0�r�[�B��F%��:i]����G�ő������6�Ypb������E��X�Nլ�6��eO���%������JF�0
�_P��: V�]�W�?�K�_kP�����t��ې�^)�W�.x����\�X��׶��s`Q+]�W���a�����qs�&�W�g��ǰ�����N�~K�(xgI���rg-(���V)�"ڲ�Ț���-��7���iŔ�Q���vïEl1|Y��W�ʤͦ�R�ٸ������V:k�b���e�k���Z6�,���R�'��*��m��+�%c4,�ˮw���×��o��X���hD�r#�˨%%8kI���mf��|���?�L����9�Y��f���}L�@M�	��n1�J�N�i����5����>^.Xx�R�ED�
#BF6��'ZIye�Vw�颰՚t���Bߵ�=��D0�XW�r%���f�>����2�t��m>+]�j���{Мi�pϱ��#)�b�Y���T�����/ dϖM<�֥���-	_׶[fo���e��Y�f��x�[�q4�W?z����ZGU�)��+�f3+˂���1;=���z�w���:���[R�X��g2��9~��C�au�;�0����i_&��v"FC?�sX�[�Jw�-2g ꕸ�ؽ��.c�ҼL�M�PFl����(r+�m��-Dj5oKɓ�m�_���M+HrZ�<j�j斓bLB��.�/���~P�3��}��xo.vx���P�0Q���ج�9��A?\�wq�s���-�XV(�4ʦ!�q��k_?ȯ6[��^���`>�.���n��SlLJ���g���aS��ҘQn޶�W���%[��v�J#�;�r#�F�V���ᭊ~���P�kӣ���m��^�о��M���76���O�z���s<��_�@�={�{R}�VBO�>	�kҸWe��^��/�tn�c���)��2��N�kᴧz k����b���d-z�\d=/�U�cX��>�֢���l�Um1�u6	Rq憧'���	�S�h��L�t��8�F���h��n�܍��=����bk��D}B��S��҆�LK�>T�����۶�*9x���s�}�DLrR�g\�-,�Jgr[[�٢0�:�j]V�d���?�]&��O����`����)���7���xj�dAɝ\����`%~G��1"
�:�9�&|&��Lg�Ipy53o,�f:�f����K�l-A3Ӓ,��F�x>N.���sE�Юd�Of���c��}+��_P�0K��1�y�4�H���W�[���t\'4�����F���+��Ѐ��Hy�L묎���̮���߆�Z�i�uuM��o�~٭c�e�����.|6!P{wCQ�/�,� �B�����-��Ͼv����?v�4&������[Ds.��\���rX��a����rVL�~>W���M��6��6�IG.�o,	��>�[���o���	F���)vC�2
��Qw9QGd6|�M�?�3��{���=�ȧPn��ފ��.��d������d��~M��½�S�W�d�'�v��4��|f�O�O�z��>�s���l��{�{Uz�~��Ao��
Q���B1���?M�tV�M�NУ�|e�H�(
�K`Q��I{�{��̟�eSCSz$ݒM�r�K�O<�Pbr�� �����>�h���ŪLw������]�\���ԡT-�]�g��D�z�9�>[��7��H�b9��϶-8%��k�t��f��P�p⠻~��#��<�3�s����^����Oܛ�q��m@ݹ��r�_�L��IqzE�^�,����hQ
�||JFR��aЋ	%������M��7���4�٪Wx\8ӛ�R��f��4��b��!H�
L_��y
sC�)��X:PI�套v�E��ж���;l�+��ρ��j]��Īsd0��ik��U,��4L�D�����	�ޗ.�d��o��|� �?��tO�U��}��Ws�k���.�m�2D.5�;ɥ���&ɯd���|�j
�҅ �!��r>")F#v�$��0p'���$�2��`�'ғKu���)�x~�j��A���Q�H�[abBS�0}Z��	� ����7���_g�y%CV�,�8�RK��\t�S.�찺S����e�R������.��|��DL������K����z��f>g����Qk�7ex%� ҫK���FՑ#C	��\Y���
(�b.�D���jPh�n�S��������s���Kϵ^TV�w�Ƞ(]����I>2~�xm�\ˊu��o���{en�I�,��.!�4:��5��>���9d�♳�V/a:�MR~�qM�XUk�ҎV�>t����ٛ�N�M�K9Ϡdi��V�B�|a��l{x��B�{�������A�{�t���y:~���}�g���oNw���g'ǧ��u�wvz�������x�o�?b�K68w�����uW�ǧ��w���Sz��M��7��lp�:����q</��+�WO|�{�K��0t�߾9y�fG��w��'!��|}���t�����)��g^'��C>��!�K��>�ì��9A
*ʏY0�;t����ރR�����Ր��y�@��1Ca�bx�s�l�<�V�i�6�1M|�@Pc�G��Sn�!�rO,1E��`�~�M@�o��tl���o�$௽�_A�*���|tS�X�����Fj�Ox�]#�_hށ��ܑ�e�f���h��A��n `B�ȟ����F�7w"�������ep�G��`"�Lɉ���o�ʟ����}��	��kv�o��>|��)s����)�����8�{�U�@��p
<�Y���N���(>��@]ęr��l`�FU��ĉRB$���5��,�~��y>(h�m���=��|�h�=L�4��~@�<���o�_��ʣDB$;�-�P����[0��3K��t�Vj���0��X��=�7O�_~��)�����3��΀3��t�&����G�(�bKB$,P��|��L�8�39��C�a.0�4�~�J
�z���_�_��v��B}`�{H�S��{��9i��f��|Dj,&�'��t�+Z�V�`�V�@q���{|����GQ6��W�1�PR��3��26�ڜɐ"���_��T��_$�w[b��+��;u.�0^bPC!1���N%�rADHC�D,�΀pb�C��Qq�s��d/�r�%y�'2�W�('V�ʟ�RH�  #����'�οz�߰����:���W_�Q�'�~�KV��7�
�#|��ɰ��8#D1���<Z����w8��H#g�t���@��{��߃����<
� nT�S�Mgų8s��<�"�0	�z�B��%p�G�ɜ%���;�"�:�.]���2����	-S�3�����^
ic\�;��=�S�,��Nm�l�fx��ċ.��-��	N8�%��s� p��a��W�㺺 Ά�qZ�J�X�џ}�*f�{�$
�!i<d��.�/I�.p����_�h�w�g䠹Px�ljR4��]r��<��w���G���u]���{�%l���U����#ֻppOc=
©�΃�xNڡ�lu%!PM"����ӛ���.�(el�d���p���i -a�9\�r}tLN`.%��\4����?���� �y@F8a9W#({�"��6θ/�7ဘ�$��pV#�&��^@ ���`�����V�Y���$Vf��i��kK�,�T+�E�s�hv�kh ��]�����v�(��8g�AU���"�Uɚ�U�깓��Н)"��ﭑާd�����D}n�z��j��1��t���ɗ����|�4N8��pՑ�1d�ihbt�q]�>� ��g4RJ��uф�Qe�K��a[�Y��a]T�п��C� �;��Jrs.�D�[vJ����@��n:�r���:�(���12��/��C����%֕�
�Poo,D�����cil���adl�����ግ;�&��"�(~��$��v6/:�\�?a��������ʒ ��g�All���p�=����Ĕ1�Aob�D���M����xƝK<s:���D��<<�������|>�p �  