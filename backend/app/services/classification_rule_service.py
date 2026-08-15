import re
from typing import Optional, List, Dict, Any
from decimal import Decimal

from sqlalchemy.orm import Session

from app.models.classification_rule import ClassificationRule
from app.models.transaction import UnifiedTransaction
from app.services.categorization_service import extract_upi_id


class ClassificationRuleService:

    @staticmethod
    def list_rules(db: Session, is_active: Optional[bool] = None) -> List[ClassificationRule]:
        query = db.query(ClassificationRule)
        if is_active is not None:
            query = query.filter(ClassificationRule.is_active == is_active)
        return query.order_by(ClassificationRule.priority.desc(), ClassificationRule.id.asc()).all()

    @staticmethod
    def get_rule(db: Session, rule_id: int) -> Optional[ClassificationRule]:
        return db.query(ClassificationRule).filter(ClassificationRule.id == rule_id).first()

    @staticmethod
    def create_rule(db: Session, **kwargs) -> ClassificationRule:
        rule = ClassificationRule(**kwargs)
        db.add(rule)
        db.commit()
        db.refresh(rule)
        return rule

    @staticmethod
    def update_rule(db: Session, rule_id: int, **kwargs) -> Optional[ClassificationRule]:
        rule = ClassificationRuleService.get_rule(db, rule_id)
        if not rule:
            return None
        
        for key, value in kwargs.items():
            if value is not None or key in ('pattern', 'upi_handle', 'amount_min', 'amount_max', 'bank_filter', 'transaction_type_filter', 'target_category_id', 'target_merchant'):
                setattr(rule, key, value)
                
        db.commit()
        db.refresh(rule)
        return rule

    @staticmethod
    def delete_rule(db: Session, rule_id: int) -> bool:
        rule = ClassificationRuleService.get_rule(db, rule_id)
        if not rule:
            return False
        db.delete(rule)
        db.commit()
        return True

    @staticmethod
    def _matches_rule(rule: ClassificationRule, transaction_dict: Dict[str, Any]) -> bool:
        # Check bank filter
        if rule.bank_filter and rule.bank_filter.upper() != str(transaction_dict.get('bank', '')).upper():
            return False
            
        # Check transaction type filter
        if rule.transaction_type_filter and rule.transaction_type_filter.upper() != str(transaction_dict.get('transaction_type', '')).upper():
            return False
            
        # Check amount
        amount = transaction_dict.get('amount')
        if amount is not None:
            if rule.amount_min is not None and amount < rule.amount_min:
                return False
            if rule.amount_max is not None and amount > rule.amount_max:
                return False
                
        # Check UPI Handle
        if rule.upi_handle:
            tx_upi = transaction_dict.get('upi_handle')
            if not tx_upi or rule.upi_handle.lower() != tx_upi.lower():
                return False
                
        # Check Pattern
        if rule.pattern:
            description = str(transaction_dict.get('description', ''))
            merchant = str(transaction_dict.get('merchant_name', ''))
            
            def _matches_text(text: str) -> bool:
                if not text:
                    return False
                if rule.pattern_is_regex:
                    try:
                        return bool(re.search(rule.pattern, text, re.IGNORECASE))
                    except re.error:
                        return False
                return rule.pattern.lower() in text.lower()
                
            if not (_matches_text(description) or _matches_text(merchant)):
                return False
                    
        return True

    @staticmethod
    def dry_run(db: Session, rule_id: int) -> Dict[str, Any]:
        rule = ClassificationRuleService.get_rule(db, rule_id)
        if not rule:
            raise ValueError(f"Rule {rule_id} not found")
            
        # Get all transactions
        transactions = db.query(UnifiedTransaction).all()
        
        matched_count = 0
        sample_transactions = []
        
        for tx in transactions:
            upi_handle = extract_upi_id(tx.description) if tx.description else None
            tx_type = tx.type.name if hasattr(tx.type, 'name') else tx.type
            tx_dict = {
                'bank': tx.bank,
                'transaction_type': tx_type,
                'amount': tx.amount,
                'upi_handle': upi_handle,
                'description': tx.description,
                'merchant_name': getattr(tx, 'merchant_name', '')
            }

            if ClassificationRuleService._matches_rule(rule, tx_dict):
                matched_count += 1
                if len(sample_transactions) < 10:  # Keep 10 samples
                    sample_transactions.append({
                        'id': tx.id,
                        'date': tx.date,
                        'description': tx.description,
                        'amount': tx.amount
                    })
                    
        return {
            "matched_count": matched_count,
            "sample_transactions": sample_transactions
        }

    @staticmethod
    def apply_rule(db: Session, rule_id: int) -> int:
        rule = ClassificationRuleService.get_rule(db, rule_id)
        if not rule:
            raise ValueError(f"Rule {rule_id} not found")
            
        from sqlalchemy import or_
        from app.models.enums import ReviewStatus
        
        # Get unclassified or NEEDS_REVIEW transactions
        transactions = db.query(UnifiedTransaction).filter(
            or_(
                UnifiedTransaction.category_id.is_(None),
                UnifiedTransaction.review_status == "NEEDS_REVIEW"
            )
        ).all()
        
        updated_count = 0
        for tx in transactions:
            upi_handle = extract_upi_id(tx.description) if tx.description else None
            tx_type = tx.type.name if hasattr(tx.type, 'name') else tx.type
            tx_dict = {
                'bank': tx.bank,
                'transaction_type': tx_type,
                'amount': tx.amount,
                'upi_handle': upi_handle,
                'description': tx.description,
                'merchant_name': getattr(tx, 'merchant_name', '')
            }

            if ClassificationRuleService._matches_rule(rule, tx_dict):
                if rule.target_category_id is not None:
                    tx.category_id = rule.target_category_id
                if rule.target_merchant:
                    tx.merchant_name = rule.target_merchant
                if rule.mark_as_transfer:
                    tx.is_transfer = True
                if rule.mark_as_excluded:
                    tx.is_excluded = True
                    
                # Mark as reviewed and track provenance
                tx.review_status = "REVIEWED"
                tx.classification_source = "AUTO_RULE"
                tx.classification_confidence = 1.0
                
                updated_count += 1
                
        if updated_count > 0:
            rule.applied_count += updated_count
            db.commit()
            
        return updated_count

    @staticmethod
    def match_transaction(db: Session, description: str, amount: Decimal, bank: str, transaction_type: str, merchant_name: str = "", upi_handle: Optional[str] = None) -> Optional[ClassificationRule]:
        rules = ClassificationRuleService.list_rules(db, is_active=True)
        
        tx_dict = {
            'description': description,
            'amount': amount,
            'bank': bank,
            'transaction_type': transaction_type,
            'upi_handle': upi_handle,
            'merchant_name': merchant_name
        }
        
        for rule in rules:
            if ClassificationRuleService._matches_rule(rule, tx_dict):
                return rule
                
        return None
