<?php
$load = sys_getloadavg();
$cpuCores = shell_exec("nproc");
if (empty($cpuCores)) { // 检查nproc命令是否返回了有效的值
    $cpuCores = 1; // 如果没有，使用默认值1
}
$cpuUsage = shell_exec("top -b -n1 | grep 'Cpu(s)' | awk '{print $2 + $4}'");
$memoryData = explode(" ", trim(shell_exec("free -m | awk 'NR==2{printf \"%.2f%% %s %s\", $3*100/$2, $3, $2 }'")));
$output = shell_exec('hostnamectl'); // 执行命令并将输出结果赋值给一个变量
$lines = explode("\n", $output); // 将输出结果按换行符分割并存储在一个数组中
foreach ($lines as $line) { // 遍历每一行
    if (preg_match('/Operating System:\s+(.+)/', $line, $matches)) { 
        $Description = $matches[1]; 
        break; // 匹配成功后使用break语句跳出循环
    }
}
foreach ($lines as $line) { // 再次遍历每一行
	if (preg_match('/Kernel:\s+(.+)/', $line, $matches)) { 
        $Kernel = $matches[1]; 
        break; // 匹配成功后使用break语句跳出循环
    }
}
foreach ($lines as $line) { // 再次遍历每一行
	if (preg_match('/Architecture:\s+(.+)/', $line, $matches)) { 
        $Architecture = $matches[1]; 
        break; // 匹配成功后使用break语句跳出循环
    }
}
foreach ($lines as $line) { // 再次遍历每一行
	if (preg_match('/Virtualization:\s+(.+)/', $line, $matches)) { 
        $Virtualization = $matches[1]; // 将值赋给Virtualization变量
        break; // 匹配成功后使用break语句跳出循环
    }
}
$virtualMachineType = shell_exec('virt-what'); // 执行命令并将输出结果赋值给一个变量
if (empty($virtualMachineType)) { // 检查virt-what命令是否返回了有效的值
    $virtualMachineType = 'None'; // 如果没有，使用默认值None
}

echo "<div>";
echo "<b>系统版本： </b>" . $Description . "<br>";
echo "<b>内核版本： </b>" . $Kernel . "<br>";
echo "<b>系统架构： </b>" . $Architecture . "<br>";
echo "<b>虚拟架构： </b>" . $Virtualization . "<br>";
echo "<br>";
echo "服务器负载： " . round($load[0]/$cpuCores*100, $cpuCores) . "%  ". round($load[0], $cpuCores) ."/". round($load[1], $cpuCores) ."/". round($load[2], $cpuCores) ."<br>";
echo "CPU核心数： " . $cpuCores . "<br>";
echo "CPU使用率： " . $cpuUsage . "%<br>";
echo "内存使用率： " . $memoryData[0] . "  ". $memoryData[1] ."/". $memoryData[2] ." (MB)<br>";
echo "</div>";
?>
