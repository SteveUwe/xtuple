CREATE OR REPLACE FUNCTION getLotSerialIds(pOrdType TEXT DEFAULT NULL,
                                           pOrdHeadId INTEGER DEFAULT NULL,
                                           pOrdItemId INTEGER DEFAULT NULL,
                                           pItemsiteId INTEGER DEFAULT NULL,
                                           pItemlocdistId INTEGER DEFAULT NULL) RETURNS INTEGER[] AS $$
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple.    
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE 
  _lsIds INTEGER[];
  _r RECORD;
BEGIN

  IF (COALESCE(pOrdType, '') <> '') THEN
    IF (pOrdItemId IS NULL) THEN
      RAISE EXCEPTION 'pOrdItemId param is required when passing pOrdType. [xtuple: getLotSerialIds, -1]';
    END IF;

    _lsIds := _lsIds || ARRAY(
      SELECT ls_id
      FROM invdetail
        JOIN invhist ON invdetail_invhist_id=invhist_id AND invhist_ordtype=pOrdType
      WHERE true
        AND CASE WHEN pOrdItemId IS NOT NULL THEN invdetail_orditem_id=pOrdItemId END
    );
  
  -- Itemsite
  ELSIF (pItemsiteId IS NOT NULL) THEN
    _lsIds := _lsIds || ARRAY(
      SELECT ls_id
      FROM ls
        JOIN itemloc ON itemloc_ls_id=ls_id
      WHERE itemloc_itemsite_id=pItemsiteId
    );

  -- Use case: user is transacting this right now and has the Create Lot Serial screen open, look for any original/outgoing inventory transactions
  ELSIF (pItemlocdistId IS NOT NULL) THEN

    SELECT * INTO _r
    FROM itemlocdist
      JOIN itemsite ON itemlocdist_itemsite_id=itemsite_id
    WHERE itemlocdist_id=pItemlocdistId;

    -- itemlocdist_invhist_id is not null
    IF (_r.itemlocdist_invhist_id IS NOT NULL) THEN
      _lsIds := _lsIds || ARRAY(
        SELECT ls_id 
        FROM invhist
          JOIN invdetail ON invhist_id=invdetail_invhist_id
          JOIN ls ON invdetail_ls_id=ls_id
        WHERE invhist_id=_r.itemlocdist_invhist_id
      );
    END IF;

    -- TODO - support for Credit Memos, Invoices, ?
    
    -- The following inv trans types should support finding the original transaction and it's ls record(s)

    -- Receiving an RA return. Get the ls records from original SO Issue to Shipping
    IF (_r.itemlocdist_order_type = 'RA' AND _r.itemlocdist_transtype = 'RR') THEN
      _lsIds := _lsIds || ARRAY(
        SELECT ls_id
        FROM raitem
          JOIN invhist ON raitem_orig_coitem_id=invhist_orditem_id AND invhist_transtype = 'SH' AND invhist_ordtype = 'SO'
          JOIN invdetail ON invhist_id=invdetail_invhist_id
          JOIN ls ON invdetail_ls_id=ls_id
        WHERE raitem_id=_r.itemlocdist_order_id
      );

    -- Returning to Shipping (SO). Get the ls records from original SO Issue to Shipping
    ELSIF (_r.itemlocdist_order_type = 'SO' AND _r.itemlocdist_transtype = 'RS') THEN
      _lsIds := _lsIds || ARRAY(
        SELECT ls_id 
        FROM coitem
          JOIN invdetail ON coitem_id=invdetail_orditem_id
          JOIN invhist ON invdetail_invhist_id=invhist_id AND invhist_transtype = 'SH' AND invhist_ordtype = 'SO'
          JOIN ls ON invdetail_ls_id=ls_id
        WHERE coitem_id=_r.itemlocdist_order_id
      );
    
    -- Returning to Shipping (TO). Get the ls records from original TO Issue to Shipping
    ELSIF (_r.itemlocdist_order_type = 'TO' AND _r.itemlocdist_transtype = 'RS') THEN
      _lsIds := _lsIds || ARRAY(
        SELECT invdetail_ls_id 
        FROM toitem
          JOIN invdetail ON toitem_id=invdetail_orditem_id
          JOIN invhist ON invdetail_invhist_id=invhist_id AND invhist_transtype = 'SH' AND invhist_ordtype = 'TO'
        WHERE toitem_id=_r.itemlocdist_order_id
          AND invdetail_ls_id IS NOT NULL
      );

    -- Receive Material (WO). Get the ls records from original Issue WO Material.
    ELSIF (_r.itemlocdist_order_type = 'WO' AND _r.itemlocdist_transtype = 'RM') THEN
      _lsIds := _lsIds || ARRAY(
        SELECT invdetail_ls_id 
        FROM womatl
          JOIN invdetail ON womatl_id=invdetail_orditem_id 
          JOIN invhist ON invdetail_invhist_id=invhist_id AND invhist_transtype = 'IM' AND invhist_ordtype = 'WO'
        WHERE womatl_id=_r.itemlocdist_order_id
          AND invdetail_ls_id IS NOT NULL
      );

    -- Receive Transfer Order. Get the ls records from the original Issue to Shipping.
    ELSIF (_r.itemlocdist_order_type = 'TO' AND _r.itemlocdist_transtype = 'TR') THEN
      _lsIds := _lsIds || ARRAY(
        SELECT ls_id 
        FROM toitem
          JOIN invdetail ON toitem=invdetail_orditem_id
          JOIN invhist ON invdetail_invhist_id=invhist_id AND invhist_transtype = 'SH' AND invhist_ordtype = 'TO'
        WHERE toitem_id=_r.itemlocdist_order_id
          AND invdetail_ls_id IS NOT NULL
      );
    END IF;

  END IF;
  
  IF (array_upper(_lsIds, 1) IS NULL) THEN
    RAISE WARNING 'Could not find any ls records for the parameters passed 
      pOrdType: %
      pOrdHeadId: %
      pOrdItemId: %
      pItemsiteId: %
      pItemlocdistId: %
      [xtuple: getLotSerialIds, -3, %, %, %, %, %].',
      pOrdType, pOrdHeadId, pOrdItemId, pItemsiteId, pItemlocdistId, pOrdType, pOrdHeadId, pOrdItemId, pItemsiteId, pItemlocdistId;
    RETURN NULL;
  ELSE 
    -- Return distinct values in array
    _lsIds := ARRAY(SELECT DISTINCT(UNNEST(_lsIds)));
    RETURN _lsIds;
  END IF;
END;

$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION getLotSerialIds(TEXT, INTEGER, INTEGER, INTEGER, INTEGER) IS 'Returns an array of ls_ids - when pItemlocdistId passed: return ls_ids tied to the current transaction.';
