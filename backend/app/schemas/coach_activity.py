from typing import List

from pydantic import BaseModel


class CoachActivitiesSet(BaseModel):
    activity_ids: List[int]


class CoachActivityOut(BaseModel):
    activity_id: int
    activity_name: str
