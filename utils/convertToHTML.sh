echo "<!DOCTYPE html>";
echo "<html>"
echo "<head>"
echo "<style>"
echo "table, th, td {"
echo "  border: 1px solid black;"
echo "}"
echo "</style>"
echo "</head>"
echo "<body>"
echo "<table>" ;
print_header=false
while read LINE ; do
  echo "<tr><td>${LINE//;/</td><td>}</td></tr>" ;
done < $1 ;
echo "</table>"
echo "</body>"
echo "</html>"
