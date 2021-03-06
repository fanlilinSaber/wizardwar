//
//  MultiplayerService.m
//  WizardWar
//
//  Created by Sean Hess on 5/29/13.
//  Copyright (c) 2013 The LAB. All rights reserved.
//

#import "MultiplayerService.h"
#import <Firebase/Firebase.h>
#import "Spell.h"
#import "Wizard.h"
#import "NSArray+Functional.h"

@interface MultiplayerService () 
@property (nonatomic, strong) Firebase * matchNode;
@property (nonatomic, strong) Firebase * spellsNode;
@property (nonatomic, strong) Firebase * playersNode;
@property (nonatomic, strong) Firebase * opponentNode;

@end

@implementation MultiplayerService
@synthesize delegate;

-(id)initWithRootRef:(Firebase*)rootRef {
    self = [super init];
    if (self) {
        self.root = rootRef;
    }
    return self;
}

-(void)connectToMatchId:(NSString*)matchId {
    
    if (!self.root) {
        NSLog(@"Cannot connect without firebase root ref");
        NSAssert(false, @"cannot connect without firebase root ref");
        return;
    }
    
    __weak MultiplayerService * wself = self;
    
    // Firebase
    self.matchNode = [[self.root childByAppendingPath:@"match"] childByAppendingPath:matchId];
    self.spellsNode = [self.matchNode childByAppendingPath:@"spells"];
    self.playersNode = [self.matchNode childByAppendingPath:@"players"];
    
    // SPELLS
    [self.spellsNode observeEventType:FEventTypeChildAdded withBlock:^(FDataSnapshot*snapshot) {
        // there is a new spell to add, add it to the queue
        Spell * spell = [Spell fromType:snapshot.value[@"type"]];
        spell.spellId = snapshot.name;
        [spell setValuesForKeysWithDictionary:snapshot.value];
        [wself.delegate mpDidAddSpell:spell];
    }];
    
    [self.spellsNode observeEventType:FEventTypeChildChanged withBlock:^(FDataSnapshot*snapshot) {
        // destroyed (strength = 0)
        // speed = 0, etc.
        [wself.delegate mpDidUpdate:snapshot.value spellWithId:snapshot.name];
    }];
    
    [self.spellsNode observeEventType:FEventTypeChildRemoved withBlock:^(FDataSnapshot*snapshot) {
        [wself.delegate mpDidRemoveSpellWithId:snapshot.name];
    }];
    
    // TODO remove spells locally after they've been destroyed for a while (finished their animations)
    
    // PLAYERS
    [self.playersNode observeEventType:FEventTypeChildAdded withBlock:^(FDataSnapshot*snapshot) {
        Wizard * player = [Wizard new];
        [player setValuesForKeysWithDictionary:snapshot.value];
        [wself.delegate mpDidAddPlayer:player];
    }];
    
    [self.playersNode observeEventType:FEventTypeChildChanged withBlock:^(FDataSnapshot*snapshot) {
        [wself.delegate mpDidUpdate:snapshot.value playerWithName:snapshot.name];
    }];
    
    [self.playersNode observeEventType:FEventTypeChildRemoved withBlock:^(FDataSnapshot*snapshot) {
        [wself.delegate mpDidRemovePlayerWithName:snapshot.name];
    }];
}

- (void)disconnect {
    [self.spellsNode removeAllObservers];
    [self.playersNode removeAllObservers];
}

- (void)addPlayer:(Wizard *)player {
    Firebase * node = [self.playersNode childByAppendingPath:player.name];
    [node onDisconnectRemoveValue];
    [node setValue:player.toObject];
}

-(void)removePlayer:(Wizard*)player {
    [[self.playersNode childByAppendingPath:player.name] removeValue];
}

- (void)updatePlayer:(Wizard *)player {
    Firebase * node = [self.playersNode childByAppendingPath:player.name];
    [node setValue:player.toObject];
}

- (void)updateSpell:(Spell *)spell {
    NSDictionary * object = spell.toObject;
    [self runWithLag:^{
        Firebase * node = [self.spellsNode childByAppendingPath:spell.spellId];
        [node setValue:object];
    }];
}

-(void)addSpell:(Spell *)spell {
    NSDictionary * object = spell.toObject;
    [self runWithLag:^{
        Firebase * node = [self.spellsNode childByAppendingPath:spell.spellId];
        [node onDisconnectRemoveValue];
        [node setValue:object];
    }];
}

-(void)removeSpells:(NSArray *)spells {
    [spells forEach:^(Spell*spell) {
        Firebase * node = [self.spellsNode childByAppendingPath:spell.spellId];
        [node removeValue];
    }];
}

-(void)runWithLag:(void(^)(void))action {
    if (self.simulatedLatency) {
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.simulatedLatency * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            action();
        });
    }
    else {
        action();
    }
}


@end
