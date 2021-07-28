package cson;

class CoolString {
    /**
     * Counts amount of times char appears in string
     * returns 0 if char is not a single character.
     * @param s 
     * @param char
     * @return Int The amount of times char was found 
     */
    public static function count(s:String, char:String):Int {
        if (char.length != 1) {
            return 0;
        }
        var coolS = s.split("");
        var amnt = 0;
        for (ch in coolS) {
            if (ch == char)
                amnt++;
        }

        return amnt;
    }
}