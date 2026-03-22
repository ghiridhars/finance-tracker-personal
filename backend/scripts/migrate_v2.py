import sys
import os

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.database import SessionLocal
from app.models.category import Category, CategoryKeyword, MccCategory
from app.models.transaction import UnifiedTransaction
from app.models.upi import UpiId
from app.services.category_service import DEFAULT_CATEGORIES

def run_migration():
    db = SessionLocal()
    
    # 1. Handle renames of existing categories (merge old into new)
    merges = {
        "Transfers": "Self Transfer",
        "Salary & Income": "Salary & Wage",
        "Bank Charges & Interest": "Bank Charges"
    }
    
    for old_name, new_name in merges.items():
        old_cat = db.query(Category).filter(Category.name == old_name).first()
        new_cat = db.query(Category).filter(Category.name == new_name).first()
        
        if old_cat and new_cat:
            print(f"Merging '{old_name}' into '{new_name}'...")
            
            # Update transactions
            db.query(UnifiedTransaction).filter(UnifiedTransaction.category_id == old_cat.id).update(
                {"category_id": new_cat.id}
            )
            # Update MCC mappings
            db.query(MccCategory).filter(MccCategory.category_id == old_cat.id).update(
                {"category_id": new_cat.id}
            )
            # Update UPI ID mappings
            db.query(UpiId).filter(UpiId.category_id == old_cat.id).update(
                {"category_id": new_cat.id}
            )
            # Delete old keywords
            db.query(CategoryKeyword).filter(CategoryKeyword.category_id == old_cat.id).delete()
            
            # Delete old category
            db.delete(old_cat)
            db.commit()
            
    # 2. Add missing categories
    for cat_data in DEFAULT_CATEGORIES:
        name = cat_data["name"]
        cat = db.query(Category).filter(Category.name == name).first()
        if not cat:
            cat = Category(
                name=name,
                icon=cat_data.get("icon", "category"),
                color=cat_data.get("color", "#BDBDBD"),
                type="expense" # generic fallback
            )
            db.add(cat)
            db.commit()
            print(f"Added new category '{name}'")
            
    # 3. Completely wipe and re-seed Keywords from the current definitive list
    # This ensures we drop old regexes or aliases that are no longer in DEFAULT_CATEGORIES
    print("Wiping old keywords and reseeding fresh from DEFAULT_CATEGORIES...")
    db.query(CategoryKeyword).delete()
    
    for cat_data in DEFAULT_CATEGORIES:
        cat = db.query(Category).filter(Category.name == cat_data["name"]).first()
        if not cat:
            continue
            
        for kw in cat_data.get("keywords", []):
            db.add(CategoryKeyword(category_id=cat.id, keyword=kw))
            
    db.commit()
    print("Migration V2 completed successfully!")
    db.close()

if __name__ == "__main__":
    run_migration()
