-- Hospital Operations Management Database
-- Analytical queries by user role
-- (synthesized data; no real patient information)

-- =====================================================================
-- A. Supply and Pharmacy Manager
-- =====================================================================

-- Q1: Items below reorder threshold, by department
SELECT s.SupplyName, s.StockLevel, s.ReorderThreshold, d.DepartmentName
FROM supplies s
JOIN departments d ON s.DepartmentID = d.DepartmentID
WHERE s.StockLevel < s.ReorderThreshold
ORDER BY (s.StockLevel - s.ReorderThreshold) ASC
LIMIT 5;

-- Q2: Items expired or expiring within 90 days, by department
SELECT d.DepartmentName,
       SUM(CASE WHEN s.ExpirationDate < CURRENT_DATE THEN 1 ELSE 0 END) AS Expired,
       SUM(CASE WHEN s.ExpirationDate BETWEEN CURRENT_DATE
                 AND DATE_ADD(CURRENT_DATE, INTERVAL 90 DAY) THEN 1 ELSE 0 END) AS ExpiringSoon,
       COUNT(s.SupplyID) AS TotalItems
FROM supplies s
JOIN departments d ON s.DepartmentID = d.DepartmentID
WHERE s.ExpirationDate IS NOT NULL
GROUP BY d.DepartmentName
ORDER BY Expired DESC
LIMIT 5;

-- Q3: Total inventory value by department
SELECT d.DepartmentName,
       COUNT(s.SupplyID) AS ItemCount,
       ROUND(SUM(s.StockLevel * s.UnitCost), 2) AS TotalValue
FROM supplies s
JOIN departments d ON s.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY TotalValue DESC
LIMIT 5;

-- =====================================================================
-- B. Infection Control Officer
-- =====================================================================

-- Q4: NICU complaint clusters (potential outbreak detection)
SELECT ChiefComplaint, COUNT(*) AS CaseCount,
       MIN(EncounterDate) AS FirstCase,
       MAX(EncounterDate) AS LastCase
FROM encounters
WHERE DepartmentID = 3
GROUP BY ChiefComplaint
ORDER BY CaseCount DESC
LIMIT 5;

-- Q5: Staff vaccination status by department
SELECT d.DepartmentName,
       COUNT(*) AS TotalStaff,
       SUM(CASE WHEN s.VaxHBVStatus  != 'complete' THEN 1 ELSE 0 END) AS HBV_Incomplete,
       SUM(CASE WHEN s.VaxTdapStatus != 'complete' THEN 1 ELSE 0 END) AS Tdap_Incomplete
FROM staff s
JOIN departments d ON s.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY HBV_Incomplete DESC
LIMIT 5;

-- Q6: Staff exposure to infection-related patients by department
SELECT s.FirstName, s.LastName, s.Role, d.DepartmentName,
       COUNT(*) AS InfectionCases
FROM encounters e
JOIN staff s       ON e.StaffID = s.StaffID
JOIN departments d ON e.DepartmentID = d.DepartmentID
WHERE e.ChiefComplaint LIKE '%fever%'
   OR e.ChiefComplaint LIKE '%infection%'
   OR e.ChiefComplaint LIKE '%gastroenteritis%'
GROUP BY s.FirstName, s.LastName, s.Role, d.DepartmentName
ORDER BY InfectionCases DESC
LIMIT 10;

-- =====================================================================
-- C. Regional Health Department Supervisor
-- =====================================================================

-- Q7: Average length of stay by department (inpatient)
SELECT d.DepartmentName,
       COUNT(*) AS Admissions,
       ROUND(AVG(DATEDIFF(e.DischargeDate, e.EncounterDate)), 1) AS AvgLOS
FROM encounters e
JOIN departments d ON e.DepartmentID = d.DepartmentID
WHERE e.EncounterType = 'inpatient' AND e.DischargeDate IS NOT NULL
GROUP BY d.DepartmentName
ORDER BY AvgLOS DESC;

-- Q8: Referral rejection rate by receiving hospital
SELECT ReceivingHospital,
       COUNT(*) AS TotalReferrals,
       SUM(CASE WHEN Status = 'rejected' THEN 1 ELSE 0 END) AS Rejected,
       ROUND(SUM(CASE WHEN Status = 'rejected' THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS RejectionPct
FROM referrals
WHERE ReferralDirection = 'outgoing'
GROUP BY ReceivingHospital
ORDER BY RejectionPct DESC;

-- Q9: Encounter volume and cost summary by visit type
SELECT EncounterType, COUNT(*) AS Total,
       ROUND(SUM(EncounterCost), 2) AS TotalCost,
       ROUND(AVG(EncounterCost), 2) AS AvgCost
FROM encounters
GROUP BY EncounterType
ORDER BY Total DESC;

-- =====================================================================
-- Queries enabled by the billing_claims and satisfaction_surveys tables
-- =====================================================================

-- Claim submission lag by department
SELECT d.DepartmentName,
       COUNT(*) AS ClaimCount,
       ROUND(AVG(DATEDIFF(bc.DateSubmitted, e.EncounterDate)), 1) AS AvgDaysToSubmit
FROM billing_claims bc
JOIN encounters e   ON bc.EncounterID = e.EncounterID
JOIN departments d  ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY AvgDaysToSubmit DESC
LIMIT 10;

-- Departments with high staff ratings but low facility ratings
SELECT d.DepartmentName,
       COUNT(*) AS Responses,
       ROUND(AVG(ss.StaffRating), 1)    AS AvgStaff,
       ROUND(AVG(ss.FacilityRating), 1) AS AvgFacility,
       ROUND(AVG(ss.StaffRating) - AVG(ss.FacilityRating), 1) AS Gap
FROM satisfaction_surveys ss
JOIN encounters e   ON ss.EncounterID = e.EncounterID
JOIN departments d  ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY Gap DESC;
