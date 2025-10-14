public class SOQLNormalizer {
    
    // Cache the regex pattern to avoid recompiling on every call
    private static final Pattern SUBQUERY_PATTERN = Pattern.compile('\\(\\s*SELECT');
    
    public static String normalize(String query) {
        if (String.isBlank(query)) {
            return '';
        }
        
        try {
            // Step 1: Normalize whitespace
            String normalized = query.trim().replaceAll('\\s+', ' ');
            
            // Check if query looks valid (starts with SELECT)
            if (!normalized.toUpperCase().startsWith('SELECT')) {
                // Invalid query - return hash
                Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(query));
                return EncodingUtil.convertToHex(hash);
            }
            
            // FAST PATH: If no subqueries, use simpler normalization
            // Check for subquery pattern: "(" followed by optional whitespace and "SELECT"
            String upperQuery = normalized.toUpperCase();
            Matcher m = SUBQUERY_PATTERN.matcher(upperQuery);
            
            if (!m.find()) {
                // No subqueries found - use fast path (still does normalization, just simpler)
                Map<String, String> clauses = extractClausesSimple(normalized);
                return rebuildQuery(clauses);
            }
            
            // SLOW PATH: Full normalization for complex queries with subqueries
            // Step 2: Extract and normalize major clauses
            Map<String, String> clauses = extractClauses(normalized);
            
            // Step 3: Rebuild normalized query
            return rebuildQuery(clauses);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Normalization failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            
            // Fallback to hash
            Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(query));
            return EncodingUtil.convertToHex(hash);
        }
    }
    
    private static Map<String, String> extractClauses(String query) {
        Map<String, String> clauses = new Map<String, String>();
        
        // Split on FROM (top-level only)
        List<String> parts = splitOnDelimiter(query, ' FROM ');
        if (parts.size() < 2) {
            return clauses; // Invalid query
        }
        
        // SELECT
        String selectPart = parts[0].trim();
        if (selectPart.toUpperCase().startsWith('SELECT')) {
            clauses.put('SELECT', normalizeFieldList(selectPart.substring(7).trim()));
        }
        
        // Everything after FROM - work backwards from the end
        String remaining = parts[1].trim();
        
        // Extract clauses that appear after FROM in reverse order
        // This way we can extract from the end and avoid conflicts
        remaining = extractClauseFromEnd(remaining, ' WITH ', clauses, 'WITH', false);
        remaining = extractClauseFromEnd(remaining, ' FOR ', clauses, 'FOR', false);
        remaining = extractClauseFromEnd(remaining, ' OFFSET ', clauses, 'OFFSET', false);
        remaining = extractClauseFromEnd(remaining, ' LIMIT ', clauses, 'LIMIT', false);
        remaining = extractClauseFromEnd(remaining, ' ORDER BY ', clauses, 'ORDER BY', true);
        remaining = extractClauseFromEnd(remaining, ' HAVING ', clauses, 'HAVING', true);
        remaining = extractClauseFromEnd(remaining, ' GROUP BY ', clauses, 'GROUP BY', true);
        remaining = extractClauseFromEnd(remaining, ' WHERE ', clauses, 'WHERE', true);
        
        // Whatever is left is the FROM object
        clauses.put('FROM', remaining.trim());
        
        return clauses;
    }
    
    // Simpler extraction for queries without subqueries (fast path)
    private static Map<String, String> extractClausesSimple(String query) {
        Map<String, String> clauses = new Map<String, String>();
        String upperQuery = query.toUpperCase();
        
        // Find keyword positions using simple indexOf (faster than split for simple queries)
        Integer fromPos = upperQuery.indexOf(' FROM ');
        if (fromPos == -1) {
            return clauses; // Invalid query
        }
        
        // Extract SELECT
        String selectPart = query.substring(7, fromPos).trim();
        clauses.put('SELECT', normalizeFieldListSimple(selectPart));
        
        // Find other clause positions
        Integer wherePos = upperQuery.indexOf(' WHERE ', fromPos);
        Integer groupPos = upperQuery.indexOf(' GROUP BY ', fromPos);
        Integer havingPos = upperQuery.indexOf(' HAVING ', fromPos);
        Integer orderPos = upperQuery.indexOf(' ORDER BY ', fromPos);
        Integer limitPos = upperQuery.indexOf(' LIMIT ', fromPos);
        Integer offsetPos = upperQuery.indexOf(' OFFSET ', fromPos);
        Integer forPos = upperQuery.indexOf(' FOR ', fromPos);
        Integer withPos = upperQuery.indexOf(' WITH ', fromPos);
        
        // Extract FROM
        Integer fromEnd = getMinPositionGreaterThan(new List<Integer>{wherePos, groupPos, orderPos, limitPos, offsetPos, forPos, withPos}, fromPos);
        if (fromEnd == -1) fromEnd = query.length();
        clauses.put('FROM', query.substring(fromPos + 6, fromEnd).trim());
        
        // Extract WHERE
        if (wherePos > -1) {
            Integer whereEnd = getMinPositionGreaterThan(new List<Integer>{groupPos, havingPos, orderPos, limitPos, offsetPos, forPos, withPos}, wherePos);
            if (whereEnd == -1) whereEnd = query.length();
            clauses.put('WHERE', normalizeWhereClause(query.substring(wherePos + 7, whereEnd).trim()));
        }
        
        // Extract GROUP BY
        if (groupPos > -1) {
            Integer groupEnd = getMinPositionGreaterThan(new List<Integer>{havingPos, orderPos, limitPos, offsetPos, forPos, withPos}, groupPos);
            if (groupEnd == -1) groupEnd = query.length();
            clauses.put('GROUP BY', normalizeFieldListSimple(query.substring(groupPos + 10, groupEnd).trim()));
        }
        
        // Extract HAVING
        if (havingPos > -1) {
            Integer havingEnd = getMinPositionGreaterThan(new List<Integer>{orderPos, limitPos, offsetPos, forPos, withPos}, havingPos);
            if (havingEnd == -1) havingEnd = query.length();
            clauses.put('HAVING', normalizeWhereClause(query.substring(havingPos + 8, havingEnd).trim()));
        }
        
        // Extract ORDER BY
        if (orderPos > -1) {
            Integer orderEnd = getMinPositionGreaterThan(new List<Integer>{limitPos, offsetPos, forPos, withPos}, orderPos);
            if (orderEnd == -1) orderEnd = query.length();
            clauses.put('ORDER BY', normalizeOrderBy(query.substring(orderPos + 10, orderEnd).trim()));
        }
        
        // Extract LIMIT
        if (limitPos > -1) {
            Integer limitEnd = getMinPositionGreaterThan(new List<Integer>{offsetPos, forPos, withPos}, limitPos);
            if (limitEnd == -1) limitEnd = query.length();
            clauses.put('LIMIT', query.substring(limitPos + 7, limitEnd).trim());
        }
        
        // Extract OFFSET
        if (offsetPos > -1) {
            Integer offsetEnd = getMinPositionGreaterThan(new List<Integer>{forPos, withPos}, offsetPos);
            if (offsetEnd == -1) offsetEnd = query.length();
            clauses.put('OFFSET', query.substring(offsetPos + 8, offsetEnd).trim());
        }
        
        // Extract FOR
        if (forPos > -1) {
            Integer forEnd = getMinPositionGreaterThan(new List<Integer>{withPos}, forPos);
            if (forEnd == -1) forEnd = query.length();
            clauses.put('FOR', query.substring(forPos + 5, forEnd).trim().toUpperCase());
        }
        
        // Extract WITH
        if (withPos > -1) {
            clauses.put('WITH', query.substring(withPos + 6).trim().toUpperCase());
        }
        
        return clauses;
    }
    
    // Helper to get minimum position greater than a threshold
    private static Integer getMinPositionGreaterThan(List<Integer> positions, Integer threshold) {
        Integer minPos = -1;
        for (Integer pos : positions) {
            if (pos > threshold && (minPos == -1 || pos < minPos)) {
                minPos = pos;
            }
        }
        return minPos;
    }
    
    // Simpler field list normalization without subquery handling
    private static String normalizeFieldListSimple(String fieldList) {
        if (String.isBlank(fieldList)) {
            return '';
        }
        
        // Simple split on comma (no parentheses handling needed)
        List<String> fields = fieldList.split(',');
        
        // Deduplicate and sort
        Set<String> seenKeys = new Set<String>();
        List<String> normalizedFields = new List<String>();
        
        for (String field : fields) {
            String trimmed = field.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            
            String dedupeKey = trimmed.toUpperCase();
            if (!seenKeys.contains(dedupeKey)) {
                seenKeys.add(dedupeKey);
                normalizedFields.add(trimmed);
            }
        }
        
        if (normalizedFields.size() > 1) {
            normalizedFields.sort();
        }
        
        return String.join(normalizedFields, ', ');
    }
    
    // Extract a clause from the end and return what remains before it
    private static String extractClauseFromEnd(String input, String keyword, Map<String, String> clauses, String clauseName, Boolean normalize) {
        List<String> parts = splitOnDelimiter(input, keyword);
        
        if (parts.size() < 2) {
            return input; // Keyword not found
        }
        
        // For keywords, we only want the LAST occurrence at top level
        // (already handled by splitOnDelimiter which splits on all occurrences)
        // We take the last part as the clause value
        String clauseValue = parts[parts.size() - 1].trim();
        
        // Reconstruct everything before the last occurrence
        List<String> beforeParts = new List<String>();
        for (Integer i = 0; i < parts.size() - 1; i++) {
            beforeParts.add(parts[i]);
        }
        String before = String.join(beforeParts, keyword);
        
        // Apply normalization if needed
        if (normalize) {
            if (clauseName == 'WHERE' || clauseName == 'HAVING') {
                clauseValue = normalizeWhereClause(clauseValue);
            } else if (clauseName == 'ORDER BY') {
                clauseValue = normalizeOrderBy(clauseValue);
            } else {
                clauseValue = normalizeFieldList(clauseValue);
            }
        } else {
            clauseValue = clauseValue.toUpperCase();
        }
        
        clauses.put(clauseName, clauseValue);
        
        return before;
    }
    
    private static String normalizeFieldList(String fieldList) {
        if (String.isBlank(fieldList)) {
            return '';
        }
        
        // Handle subqueries - don't split inside parentheses
        List<String> fields = splitRespectingParentheses(fieldList, ',');
        
        // Use a SET to track what we've seen (for deduplication)
        Set<String> seenKeys = new Set<String>();
        List<String> normalizedFields = new List<String>();
        
        for (String field : fields) {
            String trimmed = field.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            
            String normalized = trimmed;
            String dedupeKey = trimmed.toUpperCase();
            
            // Check if this is a subquery
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                // Extract subquery content
                String subquery = trimmed.substring(1, trimmed.length() - 1).trim();
                
                // Recursively normalize the subquery
                if (subquery.toUpperCase().startsWith('SELECT')) {
                    String normalizedSubquery = normalize(subquery);
                    normalized = '(' + normalizedSubquery + ')';
                    dedupeKey = normalized.toUpperCase();
                }
            }
            
            // Add only if we haven't seen this field before
            if (!seenKeys.contains(dedupeKey)) {
                seenKeys.add(dedupeKey);
                normalizedFields.add(normalized);
            }
        }
        
        // Sort fields alphabetically
        if (normalizedFields.size() > 1) {
            normalizedFields.sort();
        }
        
        return String.join(normalizedFields, ', ');
    }
    
    private static String normalizeWhereClause(String whereClause) {
        if (String.isBlank(whereClause)) {
            return '';
        }
        
        // Check if there are any OR operators (case-insensitive)
        String upperWhere = whereClause.toUpperCase();
        Boolean hasOr = upperWhere.contains(' OR ');
        
        if (hasOr) {
            // Don't normalize if OR is present (preserve logic)
            return whereClause;
        }
        
        // Split on AND, respecting parentheses
        List<String> conditions = splitOnDelimiter(whereClause, ' AND ');
        
        // Trim conditions
        List<String> normalizedConditions = new List<String>();
        for (String condition : conditions) {
            String normalized = condition.trim();
            if (String.isNotBlank(normalized)) {
                normalizedConditions.add(normalized);
            }
        }
        
        // Sort conditions
        if (normalizedConditions.size() > 1) {
            normalizedConditions.sort();
        }
        
        return String.join(normalizedConditions, ' AND ');
    }
    
    private static String normalizeOrderBy(String orderByClause) {
        if (String.isBlank(orderByClause)) {
            return '';
        }
        
        // Split on comma, respecting parentheses (for functions)
        List<String> fields = splitRespectingParentheses(orderByClause, ',');
        
        // Normalize each field
        List<String> normalizedFields = new List<String>();
        for (String field : fields) {
            String normalized = field.trim().replaceAll('\\s+', ' ');
            if (String.isNotBlank(normalized)) {
                // Uppercase ASC/DESC and NULLS FIRST/LAST
                normalized = normalized.replaceAll('(?i)\\bASC\\b', 'ASC');
                normalized = normalized.replaceAll('(?i)\\bDESC\\b', 'DESC');
                normalized = normalized.replaceAll('(?i)\\bNULLS\\s+FIRST\\b', 'NULLS FIRST');
                normalized = normalized.replaceAll('(?i)\\bNULLS\\s+LAST\\b', 'NULLS LAST');
                normalizedFields.add(normalized);
            }
        }
        
        // Sort fields
        if (normalizedFields.size() > 1) {
            normalizedFields.sort();
        }
        
        return String.join(normalizedFields, ', ');
    }
    
    private static List<String> splitRespectingParentheses(String input, String delimiter) {
        List<String> result = new List<String>();
        
        if (String.isBlank(input)) {
            return result;
        }
        
        Integer depth = 0;
        Integer start = 0;
        Boolean inString = false;
        
        for (Integer i = 0; i < input.length(); i++) {
            Integer c = input.charAt(i);
            
            // Track string literals
            if (c == 39) { // Single quote
                if (i + 1 < input.length() && input.charAt(i + 1) == 39) {
                    i++; // Skip escaped quote
                } else {
                    inString = !inString;
                }
                continue;
            }
            
            if (inString) continue;
            
            // Track parentheses depth
            if (c == 40) { // (
                depth++;
            } else if (c == 41) { // )
                depth--;
            } else if (depth == 0) {
                // Check for delimiter at top level
                if (i + delimiter.length() <= input.length()) {
                    String substr = input.substring(i, Math.min(i + delimiter.length(), input.length()));
                    if (substr == delimiter) {
                        result.add(input.substring(start, i));
                        start = i + delimiter.length();
                        i = start - 1; // Will be incremented by loop
                    }
                }
            }
        }
        
        // Add remaining
        if (start < input.length()) {
            result.add(input.substring(start));
        }
        
        return result;
    }
    
    private static List<String> splitOnDelimiter(String input, String delimiter) {
        List<String> result = new List<String>();
        
        if (String.isBlank(input)) {
            return result;
        }
        
        Integer depth = 0;
        Integer start = 0;
        Boolean inString = false;
        String upperInput = input.toUpperCase();
        String upperDelimiter = delimiter.toUpperCase();
        
        for (Integer i = 0; i < input.length(); i++) {
            Integer c = input.charAt(i);
            
            // Track string literals
            if (c == 39) { // Single quote
                if (i + 1 < input.length() && input.charAt(i + 1) == 39) {
                    i++; // Skip escaped quote
                } else {
                    inString = !inString;
                }
                continue;
            }
            
            if (inString) continue;
            
            // Track parentheses depth
            if (c == 40) { // (
                depth++;
            } else if (c == 41) { // )
                depth--;
            } else if (depth == 0) {
                // Check for delimiter at top level (case-insensitive)
                if (i + delimiter.length() <= input.length()) {
                    String substr = upperInput.substring(i, Math.min(i + delimiter.length(), upperInput.length()));
                    if (substr == upperDelimiter) {
                        result.add(input.substring(start, i));
                        start = i + delimiter.length();
                        i = start - 1; // Will be incremented by loop
                    }
                }
            }
        }
        
        // Add remaining
        if (start < input.length()) {
            result.add(input.substring(start));
        }
        
        return result;
    }
    
    private static String rebuildQuery(Map<String, String> clauses) {
        List<String> parts = new List<String>();
        
        if (clauses.containsKey('SELECT')) {
            parts.add('SELECT ' + clauses.get('SELECT'));
        }
        
        if (clauses.containsKey('FROM')) {
            parts.add('FROM ' + clauses.get('FROM'));
        }
        
        if (clauses.containsKey('WHERE')) {
            parts.add('WHERE ' + clauses.get('WHERE'));
        }
        
        if (clauses.containsKey('GROUP BY')) {
            parts.add('GROUP BY ' + clauses.get('GROUP BY'));
        }
        
        if (clauses.containsKey('HAVING')) {
            parts.add('HAVING ' + clauses.get('HAVING'));
        }
        
        if (clauses.containsKey('ORDER BY')) {
            parts.add('ORDER BY ' + clauses.get('ORDER BY'));
        }
        
        if (clauses.containsKey('LIMIT')) {
            parts.add('LIMIT ' + clauses.get('LIMIT'));
        }
        
        if (clauses.containsKey('OFFSET')) {
            parts.add('OFFSET ' + clauses.get('OFFSET'));
        }
        
        if (clauses.containsKey('FOR')) {
            parts.add('FOR ' + clauses.get('FOR'));
        }
        
        if (clauses.containsKey('WITH')) {
            parts.add('WITH ' + clauses.get('WITH'));
        }
        
        return String.join(parts, ' ');
    }
    
    public class NormalizationException extends Exception {}
}