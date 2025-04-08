use  ecommerce;
-- adding primary keys to all table--
-- INVOICE--
alter table invoice add primary key(order_id);
-- ORDERS(since there are duplicates we will handle them before changing primary key)--
create table orders_new like orders;
alter table orders_new add primary key (ExternOrderId);

insert ignore into orders_new
select * from orders
order by ExternOrderId;

select count(*) from orders;
select count(*) from orders_new;

rename table orders to orders_old,orders_new to orders;

drop table orders_old;
show index from orders where key_name = "primary";
--
-- SKU--
alter table sku_master add primary key (SKU);
-- PINCODES(we also need to handle duplicates here)--
select Warehouse_Pincode,Customer_pincode, count(*) as count
from pincodes
group by Warehouse_Pincode, Customer_pincode
having count > 1;

create table pincode_temp as select distinct
warehouse_pincode,Customer_pincode,Zone 
from pincodes;

drop table pincodes;
rename table pincode_temp to pincodes;
alter table pincodes add primary key(Warehouse_Pincode,Customer_Pincode);

-- ADDING FOREIGN KEYS --
alter table invoice
add constraint fk_invoice_order
foreign key (order_id) references orders(ExternOrderId);

alter table orders
add constraint fk_orders_SKU
foreign key (SKU) references sku_master(SKU);

alter table invoice
add constraint fk_invoice_pincode
foreign key (warehouse_pincode,customer_pincode)
references pincodes(warehouse_pincode,customer_pincode);

-- checking For Null values --
-- invoice--
-- Count null per coloumn--
select 
count(*) -count(AWB_Code) as missing_AWB_Code,
count(*) -count(Order_Id) as missing_Order_Id,
count(*) -count(Charged_Weight) as missing_weights,
count(*) -count(warehouse_pincode) as missing_warehouse_pincode,
count(*) -count(customer_pincode) as missing_customer_pincode,
count(*) -count(zone) as missing_zone,
count(*) -count(Type_of_Shipment) as missing_Type_of_Shipment,
count(*) -count(Billing_Amount) as missing_Billing_Amount
from invoice;
-- find complete row with nulls--
select * 
from invoice
where order_id is null
or AWB_Code is null
or Charged_Weight is null
or warehouse_pincode is null
or customer_pincode is null
or zone is null
or Type_of_Shipment is null
or Billing_Amount is null;
-- orders--
-- Count null per coloumn--
select 
count(*) -count(ExternOrderId) as missing_ExternOrderId,
count(*) -count(SKU) as missing_SKU,
count(*) -count(Order_Qty) as missing_Order_Qty
from orders;
-- find complete row with nulls--
select *
from orders
where ExternOrderId is null
or sku is null
or Order_Qty is null;
-- pincodes--
-- Count null per coloumn--
select 
count(*) -count(warehouse_pincode) as missing_warehouse_pincode,
count(*) -count(Customer_pincode) as missing_Customer_pincode,
count(*) -count(Zone) as missing_zone
from pincodes;
-- find complete row with nulls--
select *
from pincodes
where warehouse_pincode is null
or Customer_pincode is null
or Zone is null;
-- sku_master -
-- Count null per coloumn--
select 
count(*) -count(Weight) as missing_Weight,
count(*) -count(SKU) as missing_SKU
from sku_master;
-- find complete row with nulls--
select * 
from sku_master
where SKU is null
or weight is null;
-- pincodes--
SELECT
COUNT(*) - COUNT(Warehouses_Pincodes) as missing_warehouse_pins,
COUNT(*) - COUNT(Customer_pincodes) as missing_customer_pins,
COUNT(*) - COUNT(Zone) as missing_zones
FROM pincodes;
SELECT *
FROM pincodes
WHERE warehouse_pincode IS NULL
OR Customer_pincode IS NULL
or Zone is null;
-- EXPLORATORY DATA ANALYSIS--
-- Analyzing order volume trends with weight using  COUNT()--
select case 
when sm.weight < 50 then '0-50kg'
when sm.weight between 50 and 100 then '50-100kg'
when sm.weight between 100 and 150 then '100-150kg'
when sm.weight between 150 and 200 then '150-200kg'
when sm.weight between 200 and 250 then '200-250kg'
when sm.weight between 250 and 300 then '250-300kg'
when sm.weight between 300 and 350 then '300-350kg'
when sm.weight between 350 and 400 then '350-400kg'
when sm.weight between 400 and 450 then '400-450kg'
when sm.weight between 450 and 500 then '450-500kg'
when sm.weight > 500 then '500kg+'
end as weight_bracket,
count(*) as order_count
from orders o
join sku_master sm on o.sku = sm.SKU
group by weight_bracket;
-- WEIGHT DISTRIBUTION ANALYSIS--
select 
min(weight) as min_weight,
max(weight) as max_weight,
avg(weight) as avg_weight,
stddev(weight) as weight_stddev
from sku_master;
-- SHIPMENT WEIGHT VARIATION--
select o.ExternOrderId,sum(s.weight * o.order_qty) as calculated_weight,
i.charged_weight,(sum(s.weight*o.order_qty) - i.charged_weight) as weight_discrepancy
from orders o
join sku_master s on o.sku = s.sku
join invoice i on o.ExternOrderId = i.Order_Id
group by o.ExternOrderId,i.Charged_Weight 
having weight_discrepancy != 0;
-- WEIGHT VALIDATION--
-- compute total order weight -
CREATE TEMPORARY TABLE expected_weights AS
SELECT 
o.ExternOrderId,o.sku,o.order_qty,sm.weight as unit_weight,
(o.order_qty * sm.weight) as total_expected_weight
FROM orders o
JOIN sku_master sm ON o.sku = sm.sku;
-- Rounding the calculated weight up to the nearest 0.5 kg--
set SQL_SAFE_UPDATES=0;
update expected_weights
set total_expected_weight=ceil(total_expected_weight*2)/2;
set SQL_SAFE_UPDATES=1;
-- comparing with invoice table and identifying descripencies --
select ew.ExternOrderId,ew.total_expected_weight as calculated_weight,i.charged_weight as invoice_weight,
round(abs(ew.total_expected_weight - i.charged_weight), 2) as weight_difference,
case 
when ew.total_expected_weight = i.charged_weight then 'Exact Match'
when abs(ew.total_expected_weight - i.charged_weight) <= 1 then 'Minor variance(<1kg)'
when abs(ew.total_expected_weight - i.charged_weight) <= 2 then 'Major variance(1-2kg)'
else 'Major Variance(>2kg)'
end as discrepancy_level,i.zone,i.Type_of_Shipment
from expected_weights ew join invoice i on ew.ExternOrderId = i.Order_Id
order by weight_difference DESC;
-- delivery area verification --
-- Create a mapping view 
CREATE OR REPLACE VIEW pincode_area_mapping AS
SELECT 
customer_pincode AS pincode,
Zone AS expected_delivery_area
FROM pincodes;
-- Compare invoice areas with mapped areas
SELECT 
i.order_id,i.customer_pincode,i.zone AS invoice_delivery_area,pm.expected_delivery_area,
CASE
WHEN i.zone = pm.expected_delivery_area THEN 'Valid'
WHEN pm.expected_delivery_area IS NULL THEN 'Pincode Not Mapped'
ELSE 'Mismatch'
END AS verification_status,
i.Type_of_Shipment,
i.billing_amount
FROM invoice i
LEFT JOIN 
pincode_area_mapping pm ON i.customer_pincode = pm.pincode
WHERE 
i.zone != pm.expected_delivery_area OR 
pm.expected_delivery_area IS NULL
ORDER BY 
verification_status, i.billing_amount DESC;
-- charge calculation and validation--
WITH calculated_charges AS (SELECT 
i.order_id,i.Type_of_Shipment,i.zone,i.charged_weight,i.Billing_Amount,
        -- Base charge from weight slab
        CASE
            WHEN i.charged_weight <= 0.5 THEN 25
            WHEN i.charged_weight <= 1 THEN 40
            WHEN i.charged_weight <= 5 THEN 75
            WHEN i.charged_weight <= 10 THEN 120
            ELSE 200
        END AS base_charge,
        -- Shipment type adjustments
        CASE 
            WHEN i.Type_of_Shipment = 'Forward Charges' THEN 0
            WHEN i.Type_of_Shipment = 'Forward and RTO Charges' THEN 35  -- RTO surcharge
            ELSE 0
        END AS shipment_surcharge,
        
        -- Zone-based delivery charges (D, B, E only)
        CASE
WHEN i.zone = 'd' THEN 50 
WHEN i.zone = 'B' THEN 25
WHEN i.zone = 'e' THEN 15
 ELSE 0  
END AS zone_surcharge
    FROM invoice i
    WHERE i.zone IN ('D', 'B', 'E')  -- 
),

final_calculations AS (
    SELECT 
        *,
        (base_charge + shipment_surcharge + zone_surcharge) AS total_calculated_charge,
        (Billing_Amount - (base_charge + shipment_surcharge + zone_surcharge)) AS charge_difference
    FROM 
        calculated_charges
)

SELECT 
    order_id,
    Type_of_Shipment,
    zone,
    charged_weight,
    base_charge,
    shipment_surcharge,
    zone_surcharge,
    total_calculated_charge,
    Billing_Amount,
    charge_difference,
    CASE 
        WHEN charge_difference > 0 THEN CONCAT('Overcharged: ₹', ROUND(charge_difference, 2))
        WHEN charge_difference < 0 THEN CONCAT('Undercharged: ₹', ABS(ROUND(charge_difference, 2)))
        ELSE 'Correct Charging'
    END AS charge_status,
    ROUND(ABS(charge_difference) * 100.0 / NULLIF(total_calculated_charge, 0), 2) AS variance_percentage
FROM 
    final_calculations
ORDER BY 
    zone, ABS(charge_difference) DESC;