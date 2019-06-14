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
�      �<�V�Ȓ����8�������13��3�`n���:�ncml�#ɐ�\f������Ŷ�?�n�%BrϞ��wbԪ��������VL������ڃoV�P�67񷵵�Tey�Z��X��x�|�z�l�7��d�ۑ��Y�!!�1��E�p���?-q2�q��o"����͍��]Jv�/Cw@׮�_��k+;������y$����p����.�hTy{��YjU������R��w|v��,��?���W�����nw����o���
�i���$k���'	�ڀ^����2B��'KVD'K��MA��hL�,���q�<=d'��x/B�~��V�!�
 k<�> ��Q@�o�(��WtLboB�Y\'4������^Df2f�`uu�
͌���K�s$�%�F6!.I�q�WIL)i�*��'Z6�qd�;$e9C�ًI��U�!VѬ��7��1��%�C����zn�?y��c�����ʫ����s|�C5 ��?�+��>�� �	\��g��/�<��09" G�Y�7��m�?���͐�����T�I��,��,r/�s���T:"���F�q�`gd� �����>�ߜ�� ��r�*Ù�g�.i��~L��X6��^t_9��%�2-��@�T���G�-��Wam\�} �1$-�<��u�m[6�HU���4oH�Y��=�g]Į7F��%˒�+-ۖ��I����k���g 	`=�|��t*1�kּ!�l�M���GQ�U��n*�p�gd����n�Ӫt߿=�4ScT]��*T:�Xk�fdiP�<ԺJ����� )�;�!+�UL��.yU�*���ɪ@Bvvr�e��d�}�4b��/�b����e>��dL ��� U�5t�&��9=?���ǫ���j���n�6_�ե_`i��4sK�a����X�1���$_��
��,�� P�"@�蒟���������Ov��h��R���5Jj��ܱ7p� l$u��{������B���x��������=�#o��8��v�w{�'N�{�{�=�{��v��#x���-��<���x��(����hG�C�k�� ݕ��_8���h5P@���H"z�v�*�:� ކ���R*E�p�>Xgc�e�A0� k� � 7a��5�!a�L"ڏ�(�,�/@��Y?f�z��VQL�ݸ?rPc�̏�K4Y���I0�2聑QII{b�d�a����������(�L����#�6L;������['��؛)�9{}ʞ�3��1� ��󧘆�]'���M��l���gi����:�;���$�����q֠-��'�#����Ù��Gޘ�ߪ��m���a�V'(S5�l�l��n�o�Pe	��A�����l��'�a�S��G�ҏ?ǂB��fUL��? /a�V�_jk?��7+���/}�����ֺ������ߣh��t��F�Rc��l̳u��w���0�3�PǺc�n�{�Z����(��K��zG��=�*�#ܧI���1��9�;e
KwW�`����JAM=�?!n���ԁ�;<�]W�pD�H#���A���nH�e�0�ʎ�i�P@�ӷG��޿��5=;���'����ᾑd5�G!��%�
X ��	l�>;qtP�1����:�/�v![t3�Kj�����R�=�M�Yɚ]p � ߜ��u�^�Lz��p�v�Fw#b�?�g�5XV�D���)�uP3@#r�/̉TO��C��h��U�V��"1.����'@$zV�I����O�X��N�X(7�Pյj�2���0�T6ٓ`!�:����aCc�RpNd;������
`��� ���v�y���`,C!� �fq,�I��˪
nu>VGv��H*p��Z쭙f��HFʲ�gR��Թ�p�Պ0������MTA?	�vJ[0 k����~T]9E�r�ub%�B�����1ٰ�1%��w1쏃�Z�]��c2
��
�)�#'�w�`�	l�#ٿؘbU$��������fUu�F '��5�qs��8x%UG�.Gx� @�s�C~�����O��b����D���J+]�R�`u4�숐s��1�_i��M�=���u0����̺2*�8�qN�B� �D�ٌ��x�P���Mm#�Q1	u� l��7,��2��JMvq^��`Q��!lm~���!A�	aDx$�PE�m�P{��D^��[�u�Uc�	6hFƤm4���*̙I����(�%��Ĥ8�/�pc�� b%��Ƣ�������`Gf�o�j�|�����w��c_�#�� VJ��P�K�7z��̣�v��Rbd_8g}�ΜK#����ś������^� v*d�Y(md���YH�Wu�Gl �,�\�<gP (H�[A*V�+���-�;�I@H���x�!��k=Pަ����wƼ4l�.%�N_'�Oca��t�
�Pa���
�8Ս|_7��bc���!8+(2�)Y� `�����?) [ ��uV��l"�L�1N��C�jizwt�z�蕭
��~w�#��}�w@��٤&�b�a���n���n���l���q���ƣ�<�_=?��)�ۍgy<(q����Y�����j��)���X4��x�{X�W)'�X�'r��=y���zWN�0�4����]���x�!s2̫��2�w�"G�z���5G�,G�6�YYߊB�r���"/MɣC&%_��_���~�|�r&����m|��~;`&^�c�V8z=�i�T�r��Ԡ�0ȉ?�3�/_o=]]��v{u}=��v�N�V[[����i7�������M��l���lZ��j� ��֛��t��?[O���__}��	���?-�����l�o'JH���{'�L�c���k��?�(LH���)b���Ȏi�?G��6��2	�<Nf�<V??�l���a����|��E��f�sS�F��{\[~p0 9�� �a�~�!��0-�DԞ���E&���m9xR3�Ч��C�@�����_�� �Uuf����1��$�Ng�_q���y�q�FM?��SNO�)��S{�څ�q�=7$�T*�Qp����E�TK#��T�g���v���cA����Z�Z���a�Ε���G��	�U67���)�1��8�6�ذ�M7�������q�P��>C�pZ�>��@��Β%��&6�Ӣ8H��#��s5 ��^1�Ζ�ʘa�?U�������1O�����7=�3�9�_�O��g�ן����.Ŕ���i ���T��?���0E�`�?N�f�mz�;=d��8�����"�|�&���bʨR�~K�_R皺��i
��ڲN&�/N��s���3/��ڐ���t`��R��O�9���&\Ec�s�W���>�0e��j�	�W�H�,ǰ�m��s���M��ţ�j���Ve(���m�C���N(noT�BN��d��ӡ�H��.ԉ���ж�<�DĴS}�`��v���6ں`��u���:u#�0��O��v�̚�����X~2/� �	!5��d�ƨ�3(�"?������gt[n�����\Q�r2��ym)FC�Av��V���~כ�V�������[�l��!Us{�ɐ&�O&�L>�Os�����F���l����GI��m�yw���#ӡ��oL�Z�*��`H�2fVe��`�80Շ_�Zv�'�N�1"��-��&��&O��Jn���~g��F���x�%+b���Нv�<ۀ����ލU,:����ӎ㜝v���o�G�ߞ�����{g�9=>;��v������|�y�#���ݚ�l����o����v;��A�X�ߣ��o{�O�����?�=˶%9���ȭ�w���!q�H4g��0�\?���W���_�qLS<���%T�8e��U���Z���jL�U��t�NG�hٶX&��
���Ӧ�:��Nl[<�Vs��ښ@��0TT[C�~�)�����D! ��*��/d"0U�)��Ap�v�\�R����{rr�{������C���
"zp���bꎅ]��X�K�jH(HD�p�:2`��^�	N�Qv`�$�ab���"�r|����`MD�1a�LQi�	oŌzdeu���[�XrD�p�Z���F�D���+���]�[�2�?�����v������~���QL^�U��] ӽ���"y'xn�8�N%t�z��T#��^��n�8&�]��T$���:X�O�Cz��ENH��0�hZ��*t���yLR׊W��|)a��0�q�:��iy��	*�x���E��n�h)C��T��,7�H���x���HP߽�/H����i.�kDp������9'��'.�DJ0+��gw���AC�?!�؛�^�=��p ����:��Ӣ�����v�/�m'_�q�[����Uc�t­�e58��97����2�ٮ�;��h��V��Q�\���^�%J�h�3?�WQ&=��&2nb��HC"<�a�ܐ��$�@,�5�"/
�b@�&���[�X� -ԩ��mX2���#�D�Lg;Yߊ
��7X����HLLЛ������6�h�e�4r���^R�&� �NDJ\������ͮ@h��ڷ�A~��x�>��/�h�c!����`[�!��G��qG!��ደ!����ĳWu�������aȈ�x	7	���ݽߜ��i���߻�݄�ɏI�G�l(�LI��1��v���K? L+��0'���s�:��� ��G?���:�'�	M���W�u/������ �;g��/��Ή���!g��],x��a�W�� ��;.�f1�K���t���P��n��QY��m1����»6�a2�]0a�뒨�Q�KU_<ru��EuO<O�������>yh<�]6�ą�-� Ik��y�S�0��ji�y.<�VF�L4�$x%3[o#��|�$r}_�Z�9�\��
qE��7�?�0,969o4��	�\ۊ��뚹n�r�T���d�Y��=�t��NN��Փ"��`���hYP#���xg���ώ��$.fQ��(�uy��=�4s��)�Ζ�'�h֢��$_m�m��
�����~@�)�)�ޠ<��G�k�_R��?�rd9�c��T��l۶2�R���뜬<Լ�@�L�����*�X��r�T�3Lv���������W&��pSA�t�=Dn'-7"l;_��̠��Z�A�9vn�o���([���Z�T��m��Jh�y���G4�U�I�$��Wڹ�"�y�ʵǼ�,r��	�2�|B�M6q���a��0�J�k�I0��k+7�8��^10/N��*J:J�/�ըc:��K|)E���^��p���p�u9X���Y�p�݃�OE;EUS#�����ͼ�/�n��:���	�^���#����`��D��c�5 �b�z�͂�z��94�[~���B|��nt]��\+�^駟��wȕg3��A�\>���)��u��Y$
��9xɌ�s�,q�U�����#��g�����Uat�V	���ï9�o=h����8��P@~���Y-���!��qys�Ut8y�P�P�ԉ��ԥ6����:s�p��&)�q~o�YP��(�I��m`'�=*���Z�,��J!x�t��_��+������I�b�6dl+�P)�f��2�#e.�5��2WH�zcJ�'kőV�}d�IM��Xȴ����f\I��D!RL5S�k6�[�`m=�c's�C�GR��q��[f��1-,�s1�r�L�!�.̶�)�<x�z��%1���m
%8J��,�9�T�<���T��(۵t�o�H�gi�d����;�.t�Y����N�M�a��ytw�%�r!���<�ueb��;�l2��-X�OXD�$�D�!#L�ah	���rk`~8f6�g *����sb��c2�T����a�6����D�r2�h!˙Pz�:�1-t�����I���I�쮔yr�{N�L����<��sک!ր�n���5�xS��(A�\�0���{v�|`�8�\`�GeJ�~I��UqΆp�-�[04�a��N����b#���/��	Ki��]�!�-[�%�U�I���-�,z���A 9��S�Љ� ���dB,�|�eN��ph�H����"R�g�|��,���ƅ�S�ts�a��	9/_%9�M�����L����on�V�o�S zv+��d�M3#���K�\n�8;׹��4	�lDQ!)��u?L�z�:su����� ���qoz�Lb����X,%i�^bo.����^�p#O����¡&�C�fP�kJ�`W!�.*Z��:�xټ OӇ	����O3���	Y�x/,i��;�-S�o`)�c
�Q��-���G6�*W��D�0-r)�s�mS�(��]�����q�e�x_�a�*�_�F�����3�����̯���$Mʢ�R�-���%���RSN���S�X��
^� {Kx�� ��7��D���A1�5�ه�O�d����pV�S���s$sk
#�C`\��m���YS�;�F�r��j��tlyO=��S��_��z���&��R��	�s���i��^G�Dm��gj�9����[ӷWh�R�Q���GT~�L��R=�Wnh�NO͆f��[L��nf��Gh��y��w�D�Y�a?��eN�+�YJ�qR�W�o��u�[<�o���!GZj��P����E�R2=i����ť�Ը1/t(H�~��I����rKu�خ�S%~ind����[�D1`�s�*s����9C� �EsQ%�ޖ�j_�.��.��U����fͷi4o�*y��#�|�6,��T��]KF��uUE#�*[�jb3~\� Ns~�������աclDb�0�Fk��Ni�=;z���ӃwG9U���1���8@�P
�5��1�Kp�(|m^P����7�c����_��	�J�4ch�Y���
_�����6<C��_��3����_��.��Y����	Y6���h���[kQ_-��ܖ,��Z�hc�lT����Dh;��(��4�Q`�*����-q��t �m���XB�A�˂A�-�0�����p��r��%�ju�-y�[���Ь��bZ�=Ck,�zc�B��z��i��;$��^�7���6�����n;,�矍>_ӎvx 6F�[�/d�BR�7G���1Vi�$'�$�kb�%N�ϱ��8���s6K���� R4��8�E=^
d~��g����� <��Z�K�F[^#��Z��l+oӍ���?EX��cU���R����o��n#U��{	Jp�����F�7��}�³�4��>��:C�>.��X�Q��&��f���f��&,L��&5���r��<�P�F�l��1Z��2��gj]��M��������' �1"�W��I~�ts4N�{�b�.s#\�2c�t3�q1|��D�k�'�|�PLX+�O�M�d�ۄ� ����� ��fv�Q�C.�&��T��Z�X��[tdbe�*���}�����4-�o&��_���+��ߴ��m��Q�p�NN�}��GH,V�+�@��5�1�L�If��$<=�Wlr̀�p�F�*���G	¥Fs6A�E�����p^�N1vG�Cm�a܅��Sz��Ʒ�n���+ڭ�t[ ��E����M�}_���T�!r��))d\n��s��{�Ay���P7��X���־?����#ʚ3�����MG�:\�p.O]�����ןah�x>��+���9�Wb�]O���'��k�i1h[�8fp����K�z/u��wT�0��m��y%ɇͻl�v�ٳ3K��
���7�%�|�ٔ�چ�{�/���PE�Fz�{B(̛�lz� t'6�IMޗ	�e��W���۲�7`���V2yu��$���]ާ����A�����{Ɠ��@������~y����n%����ή����
T���0�����5����S<�QKx��.�B-�eFr�0z����t_�f�f?Ze�q�r1gOG"�>�f��������_h�����>��~`za���xKo*�������%�A�*�1�����pu�V�[G�J��P�����[���EF=� ����gG@J�_zR[���]��VL�M0��	�z�����@��h�D���Vd��j;��iپ ��j͈5^����J���k5�O6CYu�zl:��w���8��Ʀ�Mե@죻���_x y�׺�,�s���Xڬ|���~W�+�{x?�7V_�bl�I�є�ˬ�#�29�����{��kb���뛹�ȩ!6���JdM�(����	��s�r�h?j��ks�$�LF<�e?6�sE��s{W��[��]���$ �j�A!`�����rn!,�J��%<+��	�6�@m��:
��ᵘ�����_	Mw�J�&�|�%��T�O/]V�oB�֬f�¯v̓7Ѽ��߼�[�:W@��u9�\� *���ͻ�/���TS�����t��My~��l_�����|UCʒ�e��*��[[��9�Eyƨߐ#ࣝ!�8���N;�=�s9�vQ�Ƨmb��x��T���~zS�~�$���W��w�M����v���n%���`Nc/=�О��g�����r��������̙�BpT�=Pz9� v#��0=�;z��h_:0"��l�� Vo�=���=�#~�O��
1�v��݆��I�Ow
�U�Thb�0�R�Q�cy�^A���8��o�~�����Y�t�����$ꞅ�Q�3e=� ½)�S�ezvƧ�L"u�(�L��	ƿ�f�ٰ��ct��v�$���(�(��_��Q�x�=���l�Z�g�`O��/�<'�lg��=��|/�kq�����6����1������o��H�e�Q�*O9���ǎՃc�-LEG�A�s���@>8�����=f$�y	+& Y�F ȳU ��%E�s��>�&�p����	�s��ބe $���`�d[����@Or�9GC��z38T?&"�,"^�w��:�,d*���r~L��%�Z��:��HR�"�� �$�%�5��e+��4A>8KH��3��	�*W��NwG�Ǉ��x���?� �y���u�� ��A�!Ϝ?��B����Rm����s�iΙ79���� м�}�dq���SL��O�bh8�9o���;�|�=���m�����u��V���������v��S0�fvx{�]b{���-M��;��F���v��ö�#���!��V�h@q�}h��@��E��?�U�a��K�	���,�6>�[X��|�GA�BN}o����6
� �y��5)pv��"�E���(�'��5�OKҷ}��/�T*�|�T0�<T;Q涛�bH��p-GU�U(s��!�v@��U`��u��0����� I�}H�赺e���/�D!} ��%[�70����V�5�]��B���Q;�	` �a/�v+)��Z-�$t�V��{���������HO�}���Ὰ󛹧�=؆��V���������i�!�>r:k� Z�{�z)�'��A��i��"�#:t���Ҭ�c�:/_�>N`���ٷ/^?;�ǥ�������'�:?�fx�i�)�O�p���=euB.P] ��p�g/y4N���)(���5���*��(@�/4���O8T�}@q��tO����}D�����s�z�=��<E����'�:���wP2�up�L}�MN"O}�A]h�8�a�+��]��;d� �A��CՋ�{�e��`���#/pS?4@�3P���5���7�y�z�,v%����)���Cc� X�Fr��Zn�W���o�߷���I0X���e0^q�阢�Eg������ �ϳ�sx�����z� �4`�}P|�e<qa�dUnj[VQl��)�y�j(*���/�8l��N���&%�F\0�i�W�~�1�� x�����-4� �";�V�;���!4d�e�|�fl�ul�c�_�P�9��i/�L?����+ e\K }�pR� ��d�A5Q��dΓF��G �t�8B��p���`1d�~��z$���v����w<�V9���;x�_C�F��� C
����8T�d�[@�y:�����P�	���Ka�1a�G�*sgl����[G��=����
cС��&�|���I_����_��T�R_��wC�w�

<�y���	��X-yi&��Y��ZC
�FϝG(g 8�N�>��9Ii�s��R/ -��\����	!#|��ra���?0r�,���G�h#'�οL�a&�*@q���o�0�>�� ��	W�ҋ����"�|��I���8#B1�;謭�@^�������3�����H��tGȂ|v������Z���F�>�3y�g��?���E��7����!��~	�b:��,�������1$�(�v����gV?����7�O��d�%��[|�om3Nmn�_�mJ�����{i�p���
�\h�?3��Hc3���a4��8�R�M;�͇��$�'�%/~g� B��|�2�%s���:�K�0�D�f�O�G�Y��Q�HB�W����)����!�sd��v ,�\�!ۃ
�p�OH���`���eUդ�"�DPo�=yq��pX3��W�8�*�Ƙ�B�:@������ȏ���o�EȂv�@?���	,Yp��%RP����6z�#T>>0>����U;L�p����mjS��Ԧ6��MmjS��Ԧ6��MmjS��Ԧ6��MmjS�����>F� �  